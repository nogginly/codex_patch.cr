require "./codex_patch/parser"
require "./codex_patch/apply"

# Parses and applies a codex patch file to a filesystem,
# yielding events for each file operation performed.
module CodexPatch
  # Applies a codex patch read from an IO stream, using `cwd` as the base directory
  # for file references in the patch file.
  # Yields an {ApplyEvent} (either a {SingleFileEvent} or {MoveFileEvent})
  # for each file operation as it is applied.
  def self.apply(patch_io : IO, cwd : String = Dir.current, & : ApplyEvent ->)
    ApplyPatch.new(cwd).apply(patch_io) { |event| yield event }
  end

  # Convenience wrapper that applies a codex patch string, using `cwd` as the base directory
  # for file references in the patch file.
  def self.apply(patch : String, cwd : String = Dir.current, & : ApplyEvent ->)
    apply(IO::Memory.new(patch), cwd) { |event| yield event }
  end
end
