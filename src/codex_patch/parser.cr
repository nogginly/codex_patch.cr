module CodexPatch
  # Represents the type of file operation for a patch hunk.
  enum HunkType
    # The hunk adds a new file.
    AddFile
    # The hunk deletes an existing file.
    DeleteFile
    # The hunk modifies an existing file's contents.
    UpdateFile
  end

  # Represents a chunk within an update-file hunk, containing
  # context, removed, and added lines that define a diff.
  class UpdateFileChunk
    # Optional context identifier to locate this chunk within the target file.
    property change_context : String?
    # Lines from the original file to find and replace.
    property old_lines : Array(String)
    # Lines that will replace old_lines.
    property new_lines : Array(String)
    # Whether this chunk is at the end of the file.
    property? is_end_of_file : Bool

    # Creates a new UpdateFileChunk with optional context, old/new line arrays, and EOF flag.
    def initialize(@change_context = nil, @old_lines = [] of String,
                   @new_lines = [] of String, @is_end_of_file = false)
    end
  end

  # Represents a single patch hunk with an operation type, target file path,
  # raw contents (for Add/Delete hunks), optional rename path, and line-level
  # chunks (for UpdateFile hunks).
  class Hunk
    # The operation type for this hunk.
    property type : HunkType
    # The file path this hunk applies to.
    property path : String
    # Raw concatenated content for Add/Delete file hunks; nil for UpdateFile hunks.
    property contents : String?
    # Optional destination path when the file is being renamed or moved.
    property move_path : String?
    # Line-level diff chunks for UpdateFile hunks.
    property chunks : Array(UpdateFileChunk)

    # Creates a new Hunk with an operation type, path, optional contents,
    # optional move path, and optional chunks.
    def initialize(@type, @path, @contents = nil, @move_path = nil, @chunks = [] of UpdateFileChunk)
    end
  end

  # Error raised when patch parsing encounters invalid or unexpected content.
  class ParseError < Exception
    # Creates a new ParseError with a message and optional line number.
    def initialize(message, @line_number : Int32? = nil)
      super(@line_number ? "Invalid hunk at line #{@line_number}: #{message}" : "Invalid patch: #{message}")
    end
  end

  # Parses codex patch format files into structured hunk objects.
  #
  # ### State Machine Architecture
  # The parser uses a state machine with modes matching the Rust implementation:
  #
  # - `NotStarted`: Expects `*** Begin Patch`
  # - `StartedPatch`: Expects hunk headers or environment ID
  # - `AddFile`: Collects `+` prefixed content lines
  # - `DeleteFile`: Expects next hunk header
  # - `UpdateFile`: Handles diff chunks with `+`, `-`, ` ` prefixes
  # - `EndedPatch`: Only allows empty lines
  #
  # ### Marker Handling
  # The parser handles all the standard markers:
  #
  # - File operation markers (`*** Add File:`, `*** Delete File:`, `*** Update File:`)
  # - Move operation marker (`*** Move to:`)
  # - Context markers (`@@`, `@@ <context>`)
  # - End markers (`*** End Patch`, `*** End of File`)
  #
  # ### Update File Chunk Logic
  # The update file parsing follows the Rust logic for handling different line types:
  #
  # - Empty lines are treated as context lines
  # - Space-prefixed lines are context (appear in both old and new)
  # - `+` prefixed lines are additions
  # - `-` prefixed lines are removals
  # - `@@` markers start new chunks with optional context
  #
  # ### Error Handling
  # Mirrors the Rust error handling with line number tracking.
  #
  # ## Usage Example
  #
  # ```
  # parser = CodexPatch::Parser.new
  # patch_content = <<-PATCH
  # *** Begin Patch
  # *** Add File: hello.txt
  # +Hello world
  # *** Update File: src/app.py
  # @@ def greet():
  # -print("Hi")
  # +print("Hello, world!")
  # *** End Patch
  # PATCH
  #
  # hunks = parser.parse(patch_content)
  # hunks.each do |hunk|
  #   puts "Hunk: #{hunk.type} #{hunk.path}"
  # end
  # ```
  #
  # ## Notes
  #
  # This implementation focuses on the core parsing logic from the streaming parser. For a complete implementation, you may want to add:
  #
  # 1. Lenient parsing mode to handle heredoc-wrapped patches.
  # 2. Streaming support for incremental parsing
  # 3. Path resolution logic for relative/absolute paths
  # 4. The actual file application logic
  #
  # The parser follows the same grammar as specified in the Rust implementation.
  class Parser
    # Parser state machine modes.
    enum Mode
      NotStarted
      StartedPatch
      AddFile
      DeleteFile
      UpdateFile
      EndedPatch
    end

    # Marker constants read from codex patch files.
    # Markers that signal the beginning or end of a patch.
    BEGIN_PATCH_MARKER = "*** Begin Patch"
    END_PATCH_MARKER   = "*** End Patch"
    # Markers that declare each type of file operation.
    ADD_FILE_MARKER    = "*** Add File: "
    DELETE_FILE_MARKER = "*** Delete File: "
    UPDATE_FILE_MARKER = "*** Update File: "
    MOVE_TO_MARKER     = "*** Move to: "
    # Markers used within UpdateFile hunks for structure.
    EOF_MARKER                  = "*** End of File"
    CHANGE_CONTEXT_MARKER       = "@@ "
    EMPTY_CHANGE_CONTEXT_MARKER = "@@"
    ENVIRONMENT_ID_MARKER       = "*** Environment ID:"

    # Collection of parsed {Hunk} objects.
    property hunks : Array(Hunk)
    # Optional environment ID from the patch header.
    property environment_id : String?
    @mode : Mode
    @line_number : Int32
    @current_hunk : Hunk?

    # Initializes the parser with an empty hunks array, no environment ID,
    # {Mode::NotStarted} mode, line number 0, and no current hunk.
    def initialize
      @hunks = [] of Hunk
      @environment_id = nil
      @mode = Mode::NotStarted
      @line_number = 0
      @current_hunk = nil
    end

    # Parses patch content (from a String or IO) into an array of {Hunk} objects.
    # Raises {ParseError} if the patch is missing `{BEGIN_PATCH_MARKER}` or
    # does not end with `{END_PATCH_MARKER}`.
    def parse(content : IO | String) : Array(Hunk)
      content.each_line do |line|
        @line_number += 1
        process_line(line)
      end

      # Handle final line without newline
      if @mode != Mode::EndedPatch
        raise ParseError.new("The last line of the patch must be '#{END_PATCH_MARKER}'")
      end

      @hunks
    end

    # Feeds a single line into the state machine based on the current {Mode}.
    # This is the central dispatch method that routes lines to the appropriate
    # handler or raises a {ParseError} for invalid input.
    private def process_line(line : String)
      trimmed = line.strip

      case @mode
      when Mode::NotStarted
        if trimmed == BEGIN_PATCH_MARKER
          @mode = Mode::StartedPatch
        else
          raise ParseError.new("The first line of the patch must be '#{BEGIN_PATCH_MARKER}'")
        end
      when Mode::StartedPatch
        parsed_hunk_headers?(trimmed) || raise_invalid_hunk_header(trimmed)
      when Mode::AddFile
        handle_add_file_line(line, trimmed)
      when Mode::DeleteFile
        handle_delete_file_line(line, trimmed)
      when Mode::UpdateFile
        handle_update_file_line(line, trimmed)
      when Mode::EndedPatch
        unless trimmed.empty?
          raise ParseError.new("The last line of the patch must be '#{END_PATCH_MARKER}'")
        end
      end
    end

    # Checks whether a trimmed line is a recognized hunk header
    # (environment ID, end-of-patch, add, delete, or update file) and
    # transitions the mode accordingly. Returns true if a header is
    # recognized, false otherwise.
    private def parsed_hunk_headers?(trimmed : String) : Bool
      # Environment ID
      if @mode == Mode::StartedPatch && trimmed.starts_with?(ENVIRONMENT_ID_MARKER) && (env_id = trimmed[ENVIRONMENT_ID_MARKER.size..]?)
        if @environment_id
          raise ParseError.new("apply_patch environment_id cannot be specified more than once")
        end
        if (env_id = env_id.strip).empty?
          raise ParseError.new("apply_patch environment_id cannot be empty")
        end
        @environment_id = env_id
        return true
      end

      parsed_end_patch_header?(trimmed) ||
        parsed_add_file_header?(trimmed) ||
        parsed_del_file_marker?(trimmed) ||
        parsed_update_file_marker?(trimmed)
    end

    # Transitions to {Mode::EndedPatch} when an end-of-patch header is
    # encountered, marking the last chunk of any current update-file hunk
    # with `is_end_of_file = true`. Returns true if handled.
    private def parsed_end_patch_header?(trimmed)
      return false unless trimmed == END_PATCH_MARKER
      ensure_update_hunk_not_empty
      if hunk = @current_hunk
        if chunk = hunk.chunks.last?
          chunk.is_end_of_file = true
        end
      end

      @mode = Mode::EndedPatch
      true
    end

    # Parses an add-file header, transitioning to {Mode::AddFile} and
    # creating a new {Hunk} with {HunkType::AddFile}. Returns true if handled.
    private def parsed_add_file_header?(trimmed)
      # Add file
      if trimmed.starts_with?(ADD_FILE_MARKER) && (path = trimmed[ADD_FILE_MARKER.size..]?)
        ensure_update_hunk_not_empty
        hunk = @current_hunk = Hunk.new(HunkType::AddFile, path.strip)
        @hunks << hunk
        @mode = Mode::AddFile
        return true
      end
      false
    end

    # Parses a delete-file header, transitioning to {Mode::DeleteFile} and
    # creating a new {Hunk} with {HunkType::DeleteFile}. Returns true if handled.
    private def parsed_del_file_marker?(trimmed)
      if trimmed.starts_with?(DELETE_FILE_MARKER) && (path = trimmed[DELETE_FILE_MARKER.size..]?)
        ensure_update_hunk_not_empty
        hunk = @current_hunk = Hunk.new(HunkType::DeleteFile, path.strip)
        @hunks << hunk
        @mode = Mode::DeleteFile
        return true
      end
      false
    end

    # Parses an update-file header, transitioning to {Mode::UpdateFile} and
    # creating a new {Hunk} with {HunkType::UpdateFile}. Returns true if handled.
    private def parsed_update_file_marker?(trimmed)
      # Update file
      if trimmed.starts_with?(UPDATE_FILE_MARKER) && (path = trimmed[UPDATE_FILE_MARKER.size..]?)
        ensure_update_hunk_not_empty
        hunk = @current_hunk = Hunk.new(HunkType::UpdateFile, path.strip)
        @hunks << hunk
        @mode = Mode::UpdateFile
        return true
      end
      false
    end

    # Handles lines inside an AddFile hunk, collecting `+`-prefixed
    # content into the current hunk's {Hunk.contents}. If the line does
    # not start with `+`, delegates to {raise_invalid_hunk_header}.
    private def handle_add_file_line(line : String, trimmed : String)
      return if parsed_hunk_headers?(trimmed)
      if line.starts_with?('+') && (content = line[1..]?) # Strip '+' prefix
        if hunk = @current_hunk
          hunk.contents = (hunk.contents || "") + content + "\n"
        end
      else
        raise_invalid_hunk_header(trimmed)
      end
    end

    # Handles lines inside a DeleteFile hunk, collecting `-`-prefixed
    # content into the current hunk's {Hunk.contents}. If the line does
    # not start with `-`, delegates to {raise_invalid_hunk_header}.
    private def handle_delete_file_line(line : String, trimmed : String)
      return if parsed_hunk_headers?(trimmed)
      if line.starts_with?('-') && (content = line[1..]?) # Strip '-' prefix
        if hunk = @current_hunk
          hunk.contents = (hunk.contents || "") + content + "\n"
        end
      else
        raise_invalid_hunk_header(trimmed)
      end
    end

    # Handles lines inside an UpdateFile hunk by matching the line against
    # all possible types (move-to, context marker, EOF, empty line,
    # added, removed, context) and delegating to the appropriate handler.
    # Raises a {ParseError} if no handler matches.
    private def handle_update_file_line(line : String, trimmed : String)
      return if parsed_hunk_headers?(trimmed)
      unless hunk = @current_hunk
        raise_parse_error("No current hunk")
      end

      handled_move_to?(hunk, trimmed) ||
        handled_context_marker?(hunk, trimmed) ||
        handled_eof_marker?(hunk, trimmed) ||
        handled_empty_line?(trimmed, hunk) ||
        handled_added_line?(line, hunk) ||
        handled_removed_line?(line, hunk) ||
        handled_context_line?(line, hunk) ||
        raise_parse_error("Unexpected line in update hunk: '#{line}'")
    end

    # Checks whether a trimmed line is a move-to header within an
    # UpdateFile hunk, setting the hunk's {Hunk.move_path}. Returns
    # true if handled.
    private def handled_move_to?(hunk : Hunk, trimmed : String) : Bool
      if trimmed.starts_with?(MOVE_TO_MARKER)
        if hunk.chunks.empty? && hunk.move_path.nil?
          if move_to = trimmed[MOVE_TO_MARKER.size..]?
            hunk.move_path = move_to.strip
            return true
          end
          raise_parse_error("Incomplete \"Add File\" header: #{trimmed}")
        end
        raise_parse_error("Unexpected \"Add File\" header: #{trimmed}")
      end
      false
    end

    # Checks whether a trimmed line is a context marker (`@@` or
    # `@@ <text>`) and creates a new {UpdateFileChunk} for it, storing
    # the optional context string. Returns true if handled.
    private def handled_context_marker?(hunk : Hunk, trimmed : String) : Bool
      if trimmed == EMPTY_CHANGE_CONTEXT_MARKER || trimmed.starts_with?(CHANGE_CONTEXT_MARKER)
        extracted = trimmed[CHANGE_CONTEXT_MARKER.size..]?
        hunk.chunks << UpdateFileChunk.new(extracted)
        return true
      end
      false
    end

    # Checks whether a trimmed line is an end-of-file marker
    # (`*** End of File`) and marks the last chunk's
    # {UpdateFileChunk#is_end_of_file} property, creating a chunk if
    # none exist yet. Returns true if handled.
    private def handled_eof_marker?(hunk : Hunk, trimmed : String) : Bool
      if trimmed == EOF_MARKER
        hunk.chunks << UpdateFileChunk.new if hunk.chunks.empty?
        chunk = hunk.chunks.last
        if chunk.old_lines.empty? && chunk.new_lines.empty?
          raise_parse_error("Update hunk does not contain any lines")
        else
          chunk.is_end_of_file = true
        end
        return true
      end
      false
    end

    # Handles empty/blank lines within an UpdateFile hunk by creating a
    # chunk and recording an empty old and new line as context. Returns
    # true if handled.
    private def handled_empty_line?(trimmed : String, hunk : Hunk) : Bool
      if trimmed.empty?
        hunk.chunks << UpdateFileChunk.new if hunk.chunks.empty?
        if chunk = hunk.chunks.last
          chunk.old_lines << ""
          chunk.new_lines << ""
        end
        return true
      end
      false
    end

    # Handles space-prefixed lines within an UpdateFile hunk, recording
    # the stripped line as both old and new (context). Returns true if
    # handled.
    private def handled_context_line?(line : String, hunk : Hunk) : Bool
      if line.starts_with?(' ') && (context = line[1..]?)
        hunk.chunks << UpdateFileChunk.new if hunk.chunks.empty?
        if chunk = hunk.chunks.last
          chunk.old_lines << context
          chunk.new_lines << context
        end
        return true
      end
      false
    end

    # Handles `+`-prefixed lines within an UpdateFile hunk, recording
    # the stripped line as a new/added line. Returns true if handled.
    private def handled_added_line?(line : String, hunk : Hunk) : Bool
      if line.starts_with?('+') && (added = line[1..]?)
        hunk.chunks << UpdateFileChunk.new if hunk.chunks.empty?
        if chunk = hunk.chunks.last
          chunk.new_lines << added
        end
        return true
      end
      false
    end

    # Handles `-`-prefixed lines within an UpdateFile hunk, recording
    # the stripped line as an old/removed line. Returns true if handled.
    private def handled_removed_line?(line : String, hunk : Hunk) : Bool
      if line.starts_with?('-') && (removed = line[1..]?)
        hunk.chunks << UpdateFileChunk.new if hunk.chunks.empty?
        if chunk = hunk.chunks.last
          chunk.old_lines << removed
        end
        return true
      end
      false
    end

    # Raises a {ParseError} if the current {Mode} is UpdateFile and the
    # current {Hunk} has no chunks and no move_path, indicating an
    # empty update hunk.
    private def ensure_update_hunk_not_empty
      if @mode == Mode::UpdateFile && (hunk = @current_hunk)
        if hunk.chunks.empty? && hunk.move_path.nil?
          raise_parse_error("Update file hunk for path '#{hunk.path}' is empty")
        end
      end
    end

    # Convenience method that raises a {ParseError} with the current
    # {Parser#line_number}. Never returns.
    private def raise_parse_error(message) : NoReturn
      raise ParseError.new(message, @line_number)
    end

    # Convenience method that raises a {ParseError} listing the valid
    # hunk header formats for an unrecognized header.
    private def raise_invalid_hunk_header(trimmed : String)
      raise_parse_error(
        "'#{trimmed}' is not a valid hunk header. Valid hunk headers: '#{ADD_FILE_MARKER}<path>', '#{DELETE_FILE_MARKER}<path>', '#{UPDATE_FILE_MARKER}<path>'"
      )
    end
  end
end
