require "./parser"
require "./seek_sequence"

module CodexPatch
  # Error raised when a patch application fails, e.g. because a file
  # to be deleted does not exist or expected diff lines are not found.
  class ApplyPatchError < Exception
  end

  # The type of file operation performed during patch application.
  enum ApplyAction
    # A new file was created.
    AddedFile
    # An existing file was modified.
    UpdatedFile
    # An existing file was removed.
    DeletedFile
    # A file was renamed or moved.
    MovedFile
  end

  # A named tuple describing a single-file operation with an action and its target file path.
  alias SingleFileEvent = NamedTuple(action: ApplyAction, file: String)
  # A named tuple describing a move/rename operation with an action and the source and destination paths.
  alias MoveFileEvent = NamedTuple(action: ApplyAction, from: String, to: String)
  # Union of the two event types yielded during patch application.
  alias ApplyEvent = SingleFileEvent | MoveFileEvent

  # Reads and applies a codex patch to the filesystem, creating, deleting,
  # updating, or renaming files. Yields {ApplyEvent}s to report each action.
  class ApplyPatch
    extend SeekSequence

    # Creates a new ApplyPatch that will operate within the directory `cwd`.
    def initialize(@cwd : String = Dir.current)
    end

    # Parses the codex patch read from `patch_io` and applies each hunk
    # to the filesystem. Yields an {ApplyEvent} for every file operation performed.
    def apply(patch_io : IO, & : ApplyEvent ->) : Nil
      parser = Parser.new

      hunks = parser.parse(patch_io)
      apply_hunks(hunks) { |event| yield event }
    end

    # Iterates over `hunks` and dispatches each to the appropriate
    # apply method based on its {HunkType}.
    private def apply_hunks(hunks : Array(Hunk), & : ApplyEvent ->) : Nil
      hunks.each do |hunk|
        case hunk.type
        when HunkType::AddFile
          apply_add_file(hunk) { |event| yield event }
        when HunkType::DeleteFile
          apply_delete_file(hunk) { |event| yield event }
        when HunkType::UpdateFile
          apply_update_file(hunk) { |event| yield event }
        end
      end
    end

    # Resolves a patch-relative file path against the working directory
    # to produce an absolute path.
    private def resolve_path(patch_path : String) : String
      File.expand_path(patch_path, @cwd)
    end

    # Writes the contents from an AddFile hunk to the target file path
    # and yields an {ApplyAction::AddedFile} event.
    private def apply_add_file(hunk : Hunk, & : ApplyEvent ->) : Nil
      path = resolve_path(hunk.path)
      File.write(path, hunk.contents)
      yield({action: ApplyAction::AddedFile, file: path})
    end

    # Deletes the file at the path specified by a DeleteFile hunk
    # and yields an {ApplyAction::DeletedFile} event.
    private def apply_delete_file(hunk : Hunk, & : ApplyEvent ->) : Nil
      path = resolve_path(hunk.path)
      File.delete(path)
      yield({action: ApplyAction::DeletedFile, file: path})
    end

    # Applies an UpdateFile hunk to the target file by computing the
    # new contents via {compute_new_content}. If the hunk includes a
    # {Hunk#move_path}, the file is renamed (write to destination,
    # delete source) and both a MovedFile and (if content changed)
    # UpdatedFile event are yielded. Otherwise an UpdatedFile event
    # is yielded only if the content actually changed.
    private def apply_update_file(hunk : Hunk, & : ApplyEvent ->) : Nil
      path = resolve_path(hunk.path)
      original = File.read(path)
      new_content = compute_new_content(original, hunk.chunks)

      if move_path = hunk.move_path
        new_path = resolve_path(move_path)
        File.write(new_path, new_content)
        File.delete(path)
        yield({action: ApplyAction::MovedFile, from: path, to: new_path})
        if original != new_content
          yield({action: ApplyAction::UpdatedFile, file: new_path})
        end
      else
        if original != new_content
          File.write(path, new_content)
          yield({action: ApplyAction::UpdatedFile, file: path})
        end
      end
    end

    # Computes the new file contents by applying `chunks` (each
    # containing old/new line patterns) to the original file.
    # Splits the original into lines, strips a trailing empty line
    # to match diff behaviour, finds each chunk's location using
    # {SeekSequence.seek_sequence}, records the replacements, and
    # applies them in reverse order to avoid index shifting.
    private def compute_new_content(original : String,
                                    chunks : Array(UpdateFileChunk)) : String
      # Split original content into lines
      original_lines = original.split('\n').map(&.strip).to_a

      # Remove trailing empty line to match diff behaviour
      original_lines.pop if original_lines.last?.try(&.empty?)

      # Compute replacements
      replacements = compute_replacements(original_lines, chunks)
      # Apply replacements in reverse order to avoid index shifting
      new_lines = apply_replacements(original_lines, replacements)

      # Add trailing newline back if needed
      new_lines << "" unless new_lines.last?.try(&.empty?)

      new_lines.join('\n')
    end

    # For each chunk, finds its location in `original_lines` using
    # {SeekSequence.seek_sequence} (optionally falling back to
    # stripping a trailing empty line, which mirrors EOF handling).
    # Returns an array of tuples containing `(start_index, old_length, new_lines)`
    # sorted by index for consistent ordering.
    private def compute_replacements(original_lines : Array(String),
                                     chunks : Array(UpdateFileChunk)) : Array(Tuple(Int32, Int32, Array(String)))
      replacements = [] of Tuple(Int32, Int32, Array(String))
      line_index = 0

      chunks.each do |chunk|
        # If chunk has change_context, find it first
        if ctx_line = chunk.change_context
          if idx = ApplyPatch.seek_sequence(original_lines, [ctx_line], line_index, chunk.is_end_of_file?)
            line_index = idx + 1
          else
            raise ApplyPatchError.new("Failed to find context '#{ctx_line}' in file")
          end
        end

        # Pure addition (no old lines)
        if chunk.old_lines.empty?
          insertion_idx = original_lines.last?.try(&.empty?) ? original_lines.size - 1 : original_lines.size
          replacements << {insertion_idx, 0, chunk.new_lines.clone}
          next
        end

        # Find old_lines in the file
        pattern = chunk.old_lines
        found = ApplyPatch.seek_sequence(original_lines, pattern, line_index, chunk.is_end_of_file?)

        new_slice = chunk.new_lines

        # Retry without trailing empty line if not found (EOF handling)
        if found.nil? && pattern.last?.try(&.empty?)
          pattern = pattern[0..-2]
          new_slice = new_slice[0..-2] if new_slice.last?.try(&.empty?)
          found = ApplyPatch.seek_sequence(original_lines, pattern, line_index, chunk.is_end_of_file?)
        end

        if start_idx = found
          replacements << {start_idx, pattern.size, new_slice.clone}
          line_index = start_idx + pattern.size
        else
          raise ApplyPatchError.new("Failed to find expected lines in file:\n#{chunk.old_lines.join('\n')}")
        end
      end

      # Sort by index for consistent ordering
      replacements.sort_by { |(idx, _, _)| idx }
    end

    # Applies a list of replacements to `lines`, processing them in
    # reverse order to avoid index shifting. Each replacement removes
    # a range of old lines and inserts the new lines in its place.
    private def apply_replacements(lines : Array(String),
                                   replacements : Array(Tuple(Int32, Int32, Array(String)))) : Array(String)
      # Apply in reverse order to avoid index shifting
      replacements.reverse_each do |(start_idx, old_len, new_segment)|
        # Remove old lines
        old_len.times { lines.delete_at(start_idx) if start_idx < lines.size }

        # Insert new lines
        new_segment.each_with_index do |new_line, offset|
          lines.insert(start_idx + offset, new_line)
        end
      end

      lines
    end
  end
end
