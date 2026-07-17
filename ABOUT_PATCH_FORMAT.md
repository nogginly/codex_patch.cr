# How to Write a V4A (Codex) Patch File

## Overview

A patch file describes a sequence of file operations wrapped in a begin/end envelope. Each operation declares what it's doing — adding a file, deleting a file, or updating an existing file.

```
*** Begin Patch
[ one or more file operations ]
*** End Patch
```

## File Operations

Three operation types are supported:

### Add File

Create a new file. Every following line must be prefixed with `+` and contributes to the file's initial contents.

```
*** Add File: hello.txt
+Hello world
+Second line
```

The file may have zero lines of content (no `+` lines), resulting in an empty file.

### Delete File

Remove an existing file. No content follows the header.

```
*** Delete File: obsolete.txt
```

### Update File

Patch an existing file in place, optionally renaming it at the same time.

```
*** Update File: src/app.py
*** Move to: src/main.py
@@ def greet():
-print("Hi")
+print("Hello, world!")
*** End Patch
```

After the `*** Update File:` header you may optionally include `*** Move to: <new path>` to rename the file.

## Hunks

An update file consists of one or more "hunks". Each hunk is introduced by a `@@` marker, optionally followed by a header indicating the class or function to which the snippet belongs:

```
@@ def greet():
```

Within a hunk, every content line starts with one of three prefixes:

|Prefix |Meaning                                            |
|-------|---------------------------------------------------|
|(space)|Context line — present in both old and new versions|
|`-`    |Removed line — removed from the file               |
|`+`    |Added line — added to the file                     |

Example hunk:

```
@@ def greet():
 def greet():
-    print("Hi")
+    print("Hello, world!")
```

**Context**: by default, 3 lines of code immediately above and below each change are shown. If a change is within 3 lines of a previous change, the earlier change's trailing context lines are NOT duplicated.

**Uniquely identifying context**: if 3 lines of context is insufficient to uniquely locate the target snippet within the file, add a `@@` header with the enclosing class or function name:

```
@@ class BaseClass
 def method():
     old line
     changed line
     new line
```

**Disambiguating repeated blocks**: if a code block repeats many times such that even a single `@@` header plus 3 lines of context cannot uniquely identify the target, chain multiple `@@` statements to narrow the search:

```
@@ class BaseClass
@@     def repeated_method():
     context line 1
     context line 2
     context line 3
-    old
+    new
```

## End of File

Hunks may optionally include an `*** End of File` marker at the end:

```
@@ def end_stuff():
    old line
-   old line
+   new line
*** End of File
```

## Environment ID

A patch may include an optional `*** Environment ID:` line immediately after `*** Begin Patch`:

```
*** Begin Patch
*** Environment ID: abc123
*** Add File: new.txt
+content
*** End Patch
```

An ID may only appear once, and must not be empty.

## Rules

- Every operation **must** include a header declaring its action (`Add File`, `Delete File`, or `Update File`).
- New lines must always be prefixed with `+`, even when creating a new file.
- File references must be **relative paths** — never absolute.

## Full Example

A single patch file can combine multiple operations:

```
*** Begin Patch
*** Add File: new_module.rb
+class NewModule
+  def self.run
+    puts "hello"
+  end
+end
*** Delete File: old_module.rb
*** Update File: src/app.py
*** Move to: src/main.py
@@ def greet():
-print("Hi")
+print("Hello, world!")
*** End Patch
```

This patch adds a new file, deletes an old one, and updates and renames a third file — all in one operation.
