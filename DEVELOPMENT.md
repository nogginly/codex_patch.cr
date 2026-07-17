# `codex_patch.cr` Development

## Dependencies

1. Make sure you have `ops` installed, in one of the following ways:
 - as a gem via `gem install ops_team` or
 - as a tool via `brew tap nickthecook/crops && brew install ops`
2. If you not using macOS, or a Linux that uses `apt`, please [install Crystal](https://crystal-lang.org/install/)

## Getting started

|Command                        |Description                                                                       |
|-------------------------------|----------------------------------------------------------------------------------|
|`ops up`                       |Gets everything setup including `crystal` via `apt` or `brew` if applicable.      |
|`ops build-debug` or `ops bd`  |Make a debug build of `benchmark` sample, in `bin/debug` folder.                  |
|`ops build-release` or `ops br`|Make a release / production build of `benchmark` sample,  in `bin/release` folder.|
|`ops lint`                     |Run `ameba` on the source code                                                    |
|`ops test`                     |Run the test specs.                                                               |
|`ops clean`                    |Remove debug and release build files                                              |
|`ops wipe`                     |In addition to cleaning, remove all compiler caches                               |

### Build the CLI

Run `ops build` to make a debug build in the `bin/debug/` folder.

Run `ops build-release` to make a release build in the `bin/release/` folder

## Implementation Design

> This started out as an AI-generated port of the Rust-based implementation that is part of the `codex` GitHub repository.

The Codex `apply_patch` system consists of a parser that reads a custom patch format and applies changes to the filesystem. The standalone executable entry point shows the essential flow: read patch from stdin or argument, parse it, and apply to files using the current working directory.

### Codex Patch Format Specification

The patch format is defined in the parser module with this grammar:

```
*** Begin Patch
*** Add File: <path>
+content line 1
+content line 2
*** Delete File: <path>
*** Update File: <path>
*** Move to: <new_path>  # optional
@@
-old line
+new line
*** End Patch
```

Key markers:
- `*** Begin Patch` / `*** End Patch` - Delimiters
- `*** Add File: ` - Add new file with following `+` prefixed lines
- `*** Delete File: ` - Remove existing file
- `*** Update File: ` - Modify existing file with unified diff format
- `*** Move to: ` - Optional rename for update operations
- `@@` - Context marker for update hunks

### Parsing Logic

The parser uses a streaming approach that handles line-by-line processing:

1. Check for patch delimiters (`*** Begin Patch`, `*** End Patch`)
2. Identify hunk type by marker (`*** Add File:`, `*** Delete File:`, `*** Update File:`)
3. For AddFile: collect subsequent `+` prefixed lines as content
4. For DeleteFile: just record the path
5. For UpdateFile: parse `*** Move to:` (optional), then parse diff chunks with `@@` context markers and `-`/`+` lines

### Hunk Processing

The core application logic processes each hunk type:

- **AddFile**: Create file with specified content
- **DeleteFile**: Read existing file (for verification/rollback), then delete
- **UpdateFile**: Read original file, compute new content from chunks, write new content, optionally move to new path

### Path Resolution

Paths in patches can be relative or absolute. The implementation resolves them against an effective current working directory.

### Notes

The Codex implementation includes lenient parsing to handle heredoc-wrapped patches from shell commands. For a standalone Crystal implementation, start with strict parsing and add lenient mode if needed.

The streaming parser in Codex supports incremental parsing for real-time UI updates.

## References

1. https://github.com/openai/codex/blob/main/codex-rs/core/prompt_with_apply_patch_instructions.md#apply_patch
2. https://codex.danielvaughan.com/2026/03/31/codex-cli-apply-patch-v4a-diff-format/

## Contributions

See [README](./README.md)
