require "../codex_patch"

# Usage string for the CLI, which applies a codex patch file to a target directory.
USAGE = <<-HELP
apply_codex_patch PATCH_FILE [ TARGET_DIR ]

Apply a codex patch to files in TARGET_DIR (defaults to the current directory).
PATCH_FILE must be a valid codex patch created by CodexPatch.
HELP

abort(USAGE) if ARGV.size.zero?

patch_file = ARGV.first
patch_cwd = ARGV[1]? || Dir.current

# Opens the patch file and applies it via {CodexPatch.apply},
# printing each yielded {CodexPatch::ApplyEvent} as a summary
# line showing the action and affected paths relative to the
# working directory.
File.open(patch_file, "r") do |patch_io|
  cwd = Dir.current
  CodexPatch.apply(patch_io, patch_cwd) do |event|
    case event
    when CodexPatch::SingleFileEvent
      file = Path.new(event[:file]).relative_to(cwd)
      puts "#{event[:action]}:\t #{file}"
    when CodexPatch::MoveFileEvent
      from = Path.new(event[:from]).relative_to(cwd)
      to = Path.new(event[:to]).relative_to(cwd)
      puts "#{event[:action]}:\t #{from} -> #{to}"
    end
  end
end
