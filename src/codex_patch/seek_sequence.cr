module CodexPatch
  # Extended mixin providing fuzzy line-sequence matching, used by
  # {ApplyPatch} to locate the position of diff hunks within existing
  # files. Matching proceeds through four passes of increasing leniency:
  # 1. Exact match
  # 2. Right-strip (ignore trailing whitespace)
  # 3. Full strip (ignore leading and trailing whitespace)
  # 4. Normalize Unicode punctuation to ASCII equivalents
  module SeekSequence
    # Finds the index of the first occurrence of `pattern` within `lines`,
    # starting the search at `start_index`. Returns `nil` if the pattern
    # is not found. When `eof` is true, blank pattern lines match at the
    # very end of the file. Matching is attempted in four passes of
    # increasing leniency (exact, right-stripped, fully stripped, Unicode-
    # normalized), mirroring `git apply`'s fuzzy behaviour.
    def seek_sequence(lines : Array(String),
                      pattern : Array(String),
                      start_index : Int32,
                      eof : Bool) : Int32?
      return nil if pattern.empty?

      # exact match first
      found = match?(lines, pattern, start_index, eof) { |line, pat| {line, pat} }
      return found if found

      # right-strip whitespace match if no exact match
      found = match?(lines, pattern, start_index, eof) do |line, pat|
        {line.try(&.rstrip), pat.rstrip}
      end
      return found if found

      # strip whitespace match as last resort, extra lenient
      found = match?(lines, pattern, start_index, eof) do |line, pat|
        {line.try(&.strip), pat.strip}
      end
      return found if found

      # ------------------------------------------------------------------
      # Final, most permissive pass - attempt to match after *normalising*
      # common Unicode punctuation to their ASCII equivalents so that diffs
      # authored with plain ASCII characters can still be applied to source
      # files that contain typographic dashes / quotes, etc.  This mirrors the
      # fuzzy behaviour of `git apply` which ignores minor byte-level
      # differences when locating context lines.
      # ------------------------------------------------------------------
      match?(lines, pattern, start_index, eof) do |line, pat|
        {
          line ? normalise(line) : nil,
          normalise(pat.strip),
        }
      end
    end

    # Internal helper that implements the core matching loop. Attempts
    # to match `pattern` within `lines` starting at `start_index`,
    # using the provided yield block to compare individual lines.
    # Returns the starting index on success or nil on failure.
    private def match?(lines : Array(String),
                       pattern : Array(String),
                       start_index : Int32,
                       eof : Bool,
                       & : String?, String -> {String?, String}) : Int32?
      start_index.upto(start_index + (lines.size - pattern.size)) do |i|
        match = true
        pattern.each_with_index do |pat_line, j|
          if eof && i + j == lines.size - 1
            # EOF tolerance - allow matching at end
            next if pat_line.empty?
          end
          line, pat_line = yield lines[i + j]?, pat_line
          if line != pat_line
            match = false
            break
          end
        end
        return i if match
      end
    end

    # Normalizes a string by trimming whitespace, then converting:
    # - various Unicode dash/hyphen characters to ASCII '-',
    # - fancy single quotes to ASCII ''',
    # - fancy double quotes to ASCII ",
    # - various Unicode space characters to ASCII ' '.
    def normalise(s : String) : String
      s.strip.each_char.map do |char|
        case char
        when '\u{2010}', '\u{2011}', '\u{2012}', '\u{2013}', '\u{2014}', '\u{2015}', '\u{2212}'
          '-'
        when '\u{2018}', '\u{2019}', '\u{201A}', '\u{201B}'
          '\''
        when '\u{201C}', '\u{201D}', '\u{201E}', '\u{201F}'
          '"'
        when '\u{00A0}', '\u{2002}', '\u{2003}', '\u{2004}', '\u{2005}', '\u{2006}', '\u{2007}', '\u{2008}', '\u{2009}', '\u{200A}', '\u{202F}', '\u{205F}', '\u{3000}'
          ' '
        else
          char
        end
      end.join
    end
  end
end
