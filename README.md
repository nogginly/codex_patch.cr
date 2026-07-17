# `codex_patch.cr`

Crystal shard that implements the Codex patch format — a stripped-down, file-oriented diff format designed to be easy to parse and safe to apply, designed for use by LLMs.

## Usage

1. Add the dependency to your `shard.yml`:

```yml
dependencies:
  codex_patch:
    github: nogginly/codex_patch.cr
```

2. Run `shards install`

3. Import the shard and use the top-level `CodexPatch.apply` method with with an `IO` (or `String`) to apply a patch to the current working directory.

```cr
require "codex_patch"

abort("Specify patch file, or - to read from standard inpput.") if ARGV.size.zero?

patch_file = ARGV.first
File.open(patch_file, "r") do |patch_io|
  cwd = Dir.current
  CodexPatch.apply(patch_io, cwd) do |event|
    puts event.inspect
  end
end
```

## CLI

> See [DEVELOPMENT.md](./DEVELOPMENT.md) for how to build the CLI.

The included `apply_codex_patch` command applies a patch file to a target directory:

```bash
apply_codex_patch PATCH_FILE [ TARGET_DIR ]

Apply a codex patch to files in TARGET_DIR (defaults to the current directory).
PATCH_FILE must be a valid codex patch created by CodexPatch.
```

## Patch file format

See [ABOUT_PATCH_FORMAT.md](./ABOUT_PATCH_FORMAT.md)

The document is intentionally separate so that you can give it to your LLM of choice to teach it how to write these patch files when using `apply_codex_patch` with your coding agent.

## Contributions, by invitation!

*With apologies*, at this time contributions are *by invitation only* and limited to people I know and see often.

These are early days for _codex_patch.cr_ and I am busy with family and work.

At this time I want to work on this at a manageable pace.
