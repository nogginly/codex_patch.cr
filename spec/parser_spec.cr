require "./spec_helper"

describe CodexPatch::Parser do
  describe "#parse" do
    describe "Add File" do
      it "parses a minimal Add File patch" do
        patch = <<-PATCH
                  *** Begin Patch
                  *** Add File: hello.txt
                  +Hello world
                  *** End Patch
                  PATCH

        parser = CodexPatch::Parser.new
        hunks = parser.parse(patch)

        hunks.size.should eq(1)
        hunks[0].type.should eq(CodexPatch::HunkType::AddFile)
        hunks[0].path.should eq("hello.txt")
        hunks[0].contents.should eq("Hello world\n")
      end

      it "parses Add File with multiple lines" do
        patch = <<-PATCH
                  *** Begin Patch
                  *** Add File: multiline.txt
                  +line 1
                  +line 2
                  +line 3
                  *** End Patch
                  PATCH

        parser = CodexPatch::Parser.new
        hunks = parser.parse(patch)

        hunks.size.should eq(1)
        hunks[0].contents.should eq("line 1\nline 2\nline 3\n")
      end

      it "parses Add File with paths containing subdirectories" do
        patch = <<-PATCH
                  *** Begin Patch
                  *** Add File: src/lib/file.cr
                  +content
                  *** End Patch
                  PATCH

        parser = CodexPatch::Parser.new
        hunks = parser.parse(patch)

        hunks[0].path.should eq("src/lib/file.cr")
      end

      it "parses Add File with empty content" do
        patch = <<-PATCH
                  *** Begin Patch
                  *** Add File: empty.txt
                  *** End Patch
                  PATCH

        parser = CodexPatch::Parser.new
        hunks = parser.parse(patch)

        hunks[0].type.should eq(CodexPatch::HunkType::AddFile)
        hunks[0].contents.should be_nil
      end

      it "strips the + prefix from each content line" do
        patch = <<-PATCH
                  *** Begin Patch
                  *** Add File: file.txt
                  +content1
                  +content2
                  +content3
                  *** End Patch
                  PATCH

        parser = CodexPatch::Parser.new
        hunks = parser.parse(patch)

        hunks[0].contents.should eq("content1\ncontent2\ncontent3\n")
      end

      it "preserves content lines that start with + but include the rest" do
        patch = <<-PATCH
                  *** Begin Patch
                  *** Add File: file.txt
                  ++ not just single plus
                  *** End Patch
                  PATCH

        parser = CodexPatch::Parser.new
        hunks = parser.parse(patch)

        hunks[0].contents.should eq("+ not just single plus\n")
      end

      it "includes empty + lines as empty content lines" do
        patch = <<-PATCH
                  *** Begin Patch
                  *** Add File: file.txt
                  +
                  *** End Patch
                  PATCH

        parser = CodexPatch::Parser.new
        hunks = parser.parse(patch)

        hunks[0].contents.should eq("\n")
      end

      it "trims whitespace from Add File path" do
        patch = <<-PATCH
                  *** Begin Patch
                  *** Add File:   hello.txt
                  +Hello
                  *** End Patch
                  PATCH

        parser = CodexPatch::Parser.new
        hunks = parser.parse(patch)

        hunks[0].path.should eq("hello.txt")
      end
    end

    describe "Delete File" do
      it "parses a Delete File hunk" do
        patch = <<-PATCH
                  *** Begin Patch
                  *** Delete File: old_file.txt
                  *** End Patch
                  PATCH

        parser = CodexPatch::Parser.new
        hunks = parser.parse(patch)

        hunks.size.should eq(1)
        hunks[0].type.should eq(CodexPatch::HunkType::DeleteFile)
        hunks[0].path.should eq("old_file.txt")
      end

      it "parses Delete File with path containing subdirectories" do
        patch = <<-PATCH
                  *** Begin Patch
                  *** Delete File: src/old/foo.cr
                  *** End Patch
                  PATCH

        parser = CodexPatch::Parser.new
        hunks = parser.parse(patch)

        hunks[0].path.should eq("src/old/foo.cr")
      end

      it "trims whitespace from Delete File path" do
        patch = <<-PATCH
                  *** Begin Patch
                  *** Delete File:   old.txt
                  *** End Patch
                  PATCH

        parser = CodexPatch::Parser.new
        hunks = parser.parse(patch)

        hunks[0].path.should eq("old.txt")
      end
    end

    describe "Update File" do
      # it "parses a simple Update File hunk" do
      #   patch = <<-PATCH
      #         *** Begin Patch
      #         *** Update File: src/app.cr
      #         *** End Patch
      #   PATCH
      #
      #   parser = CodexPatch::Parser.new
      #   hunks = parser.parse(patch)
      #
      #   hunks.size.should eq(1)
      #   hunks[0].type.should eq(CodexPatch::HunkType::UpdateFile)
      #   hunks[0].path.should eq("src/app.cr")
      # end

      it "parses Update File with single context line using empty @@ marker" do
        patch = <<-PATCH
                  *** Begin Patch
                  *** Update File: file.txt
                  @@
                  - old line
                  *** End Patch
                  PATCH

        parser = CodexPatch::Parser.new
        hunks = parser.parse(patch)

        hunk = hunks[0]
        hunk.type.should eq(CodexPatch::HunkType::UpdateFile)
        hunk.path.should eq("file.txt")
        chunk = hunk.chunks[0]
        chunk.change_context.should be_nil
        chunk.old_lines.should eq([" old line"])
        chunk.new_lines.should be_empty
      end

      it "parses Update File with context marker containing text" do
        patch = <<-PATCH
                  *** Begin Patch
                  *** Update File: file.txt
                  @@ def hello()
                  - old
                  + new
                  *** End Patch
                  PATCH

        parser = CodexPatch::Parser.new
        hunks = parser.parse(patch)

        chunk = hunks[0].chunks[0]
        chunk.change_context.should eq("def hello()")
        chunk.old_lines.should eq([" old"])
        chunk.new_lines.should eq([" new"])
        chunk.is_end_of_file?.should be_true
      end

      it "parses Update File with addition line" do
        patch = <<-PATCH
                  *** Begin Patch
                  *** Update File: file.txt
                  @@
                  + new line
                  *** End Patch
                  PATCH

        parser = CodexPatch::Parser.new
        hunks = parser.parse(patch)

        chunk = hunks[0].chunks[0]
        chunk.old_lines.should eq([] of String)
        chunk.new_lines.should eq([" new line"])
      end

      it "parses Update File with removal line" do
        patch = <<-PATCH
                  *** Begin Patch
                  *** Update File: file.txt
                  @@
                  -removed line
                  *** End Patch
                  PATCH

        parser = CodexPatch::Parser.new
        hunks = parser.parse(patch)

        chunk = hunks[0].chunks[0]
        chunk.old_lines.should eq(["removed line"])
        chunk.new_lines.should eq([] of String)
      end

      it "parses Update File with empty line as context" do
        patch = <<-PATCH
                  *** Begin Patch
                  *** Update File: file.txt
                  @@

                    next line
                  *** End Patch
                  PATCH

        parser = CodexPatch::Parser.new
        hunks = parser.parse(patch)

        chunk = hunks[0].chunks[0]
        chunk.old_lines.should eq(["", " next line"])
        chunk.new_lines.should eq(["", " next line"])
        chunk.is_end_of_file?.should be_true
      end

      it "parses Update File with multiple chunks" do
        patch = <<-PATCH
                  *** Begin Patch
                  *** Update File: file.txt
                  @@ old1 @@
                  - old1
                  + new1
                  @@ old2
                  - old2
                  + new2
                  *** End Patch
                  PATCH

        parser = CodexPatch::Parser.new
        hunks = parser.parse(patch)

        hunks[0].chunks.size.should eq(2)
        hunks[0].chunks[0].old_lines.should eq([" old1"])
        hunks[0].chunks[0].new_lines.should eq([" new1"])
        hunks[0].chunks[1].old_lines.should eq([" old2"])
        hunks[0].chunks[1].new_lines.should eq([" new2"])
      end

      it "parses Update File with EOF marker" do
        patch = <<-PATCH
                  *** Begin Patch
                  *** Update File: file.txt
                  @@ old @@
                   old
                   new
                  *** End of File
                  *** End Patch
                  PATCH

        parser = CodexPatch::Parser.new
        hunks = parser.parse(patch)

        hunks[0].chunks[0].is_end_of_file?.should be_true
      end

      it "parses Update File with move path" do
        patch = <<-PATCH
                  *** Begin Patch
                  *** Update File: old.txt
                  *** Move to: new.txt
                  @@ old @@
                   old
                   new
                  *** End Patch
                  PATCH

        parser = CodexPatch::Parser.new
        hunks = parser.parse(patch)

        hunks[0].move_path.should eq("new.txt")
      end

      it "parses Update File with move path containing subdirectories" do
        patch = <<-PATCH
                  *** Begin Patch
                  *** Update File: src/old.cr
                  *** Move to: lib/new.cr
                  @@ old @@
                   old
                   new
                  *** End Patch
                  PATCH

        parser = CodexPatch::Parser.new
        hunks = parser.parse(patch)

        hunks[0].move_path.should eq("lib/new.cr")
      end

      it "parses Update File with no chunks (raises error)" do
        patch = <<-PATCH
                  *** Begin Patch
                  *** Update File: file.txt
                  *** End Patch
                  PATCH

        parser = CodexPatch::Parser.new
        expect_raises(CodexPatch::ParseError, /empty/) do
          parser.parse(patch)
        end
      end

      it "trims whitespace from Update File path" do
        patch = <<-PATCH
                  *** Begin Patch
                  *** Update File:   file.txt
                  @@ old @@
                   old
                   new
                  *** End Patch
                  PATCH

        parser = CodexPatch::Parser.new
        hunks = parser.parse(patch)

        hunks[0].path.should eq("file.txt")
      end

      it "trims whitespace from Move to path" do
        patch = <<-PATCH
                  *** Begin Patch
                  *** Update File: old.txt
                  *** Move to:   new.txt
                  @@ old @@
                   old
                   new
                  *** End Patch
                  PATCH

        parser = CodexPatch::Parser.new
        hunks = parser.parse(patch)

        hunks[0].move_path.should eq("new.txt")
      end
    end

    describe "Multiple hunks in one patch" do
      it "parses Add, Delete, and Update hunks together" do
        patch = <<-PATCH
                  *** Begin Patch
                  *** Add File: new.txt
                  +content
                  *** Delete File: old.txt
                  *** Update File: change.txt
                  @@ old @@
                   old
                   new
                  *** End Patch
                  PATCH

        parser = CodexPatch::Parser.new
        hunks = parser.parse(patch)

        hunks.size.should eq(3)
        hunks[0].type.should eq(CodexPatch::HunkType::AddFile)
        hunks[1].type.should eq(CodexPatch::HunkType::DeleteFile)
        hunks[2].type.should eq(CodexPatch::HunkType::UpdateFile)
      end

      it "parses multiple Add File hunks" do
        patch = <<-PATCH
                  *** Begin Patch
                  *** Add File: a.txt
                  +a
                  *** Add File: b.txt
                  +b
                  *** End Patch
                  PATCH

        parser = CodexPatch::Parser.new
        hunks = parser.parse(patch)

        hunks.size.should eq(2)
        hunks[0].path.should eq("a.txt")
        hunks[1].path.should eq("b.txt")
      end

      it "parses multiple Add File hunks in correct order" do
        patch = <<-PATCH
                  *** Begin Patch
                  *** Add File: first.txt
                  +first
                  *** Add File: second.txt
                  +second
                  *** End Patch
                  PATCH

        parser = CodexPatch::Parser.new
        hunks = parser.parse(patch)

        hunks.size.should eq(2)
        hunks[0].contents.should eq("first\n")
        hunks[1].contents.should eq("second\n")
      end

      it "parses multiple Delete File hunks" do
        patch = <<-PATCH
                  *** Begin Patch
                  *** Delete File: a.txt
                  *** Delete File: b.txt
                  *** End Patch
                  PATCH

        parser = CodexPatch::Parser.new
        hunks = parser.parse(patch)

        hunks.size.should eq(2)
        hunks[0].path.should eq("a.txt")
        hunks[1].path.should eq("b.txt")
      end

      it "parses multiple Update File hunks" do
        patch = <<-PATCH
                  *** Begin Patch
                  *** Update File: a.txt
                  @@ old1 @@
                   old1
                   new1
                  *** Update File: b.txt
                  @@ old2 @@
                   old2
                   new2
                  *** End Patch
                  PATCH

        parser = CodexPatch::Parser.new
        hunks = parser.parse(patch)

        hunks.size.should eq(2)
        hunks[0].path.should eq("a.txt")
        hunks[1].path.should eq("b.txt")
      end

      it "parses a complex patch with all hunk types" do
        patch = <<-PATCH
                  *** Begin Patch
                  *** Add File: new.txt
                  +new content
                  *** Delete File: old.txt
                  *** Update File: change.txt
                  @@ old1 @@
                  - old1
                  + new1
                  *** Update File: this.txt
                  *** Move to: else/there.txt
                  @@ old2 @@
                  - old2
                  + new2
                  *** End Patch
                  PATCH

        parser = CodexPatch::Parser.new
        hunks = parser.parse(patch)

        hunks.size.should eq(4)
        hunks[0].type.should eq(CodexPatch::HunkType::AddFile)
        hunks[0].contents.should eq("new content\n")

        hunks[1].type.should eq(CodexPatch::HunkType::DeleteFile)
        hunks[1].path.should eq("old.txt")

        hunks[2].type.should eq(CodexPatch::HunkType::UpdateFile)
        hunks[2].path.should eq("change.txt")

        hunks[3].type.should eq(CodexPatch::HunkType::UpdateFile)
        hunks[3].move_path.should eq("else/there.txt")
        hunks[3].chunks.size.should eq(1)
      end
    end

    describe "Environment ID" do
      it "parses a patch with environment ID" do
        patch = <<-PATCH
                  *** Begin Patch
                  *** Environment ID: abc123
                  *** Add File: hello.txt
                  +Hello
                  *** End Patch
                  PATCH

        parser = CodexPatch::Parser.new
        hunks = parser.parse(patch)

        parser.environment_id.should eq("abc123")
        hunks.size.should eq(1)
      end

      it "parses environment ID with surrounding whitespace" do
        patch = <<-PATCH
                  *** Begin Patch
                  *** Environment ID:   abc123
                  *** Add File: hello.txt
                  +Hello
                  *** End Patch
                  PATCH

        parser = CodexPatch::Parser.new
        hunks = parser.parse(patch)

        parser.environment_id.should eq("abc123")
      end

      it "trims whitespace from environment ID" do
        patch = <<-PATCH
                  *** Begin Patch
                  *** Environment ID:  abc123
                  *** Add File: x.txt
                  +y
                  *** End Patch
                  PATCH

        parser = CodexPatch::Parser.new
        hunks = parser.parse(patch)

        parser.environment_id.should eq("abc123")
      end

      it "rejects duplicate environment IDs" do
        patch = <<-PATCH
                  *** Begin Patch
                  *** Environment ID: abc
                  *** Environment ID: def
                  *** Add File: hello.txt
                  +Hello
                  *** End Patch
                  PATCH

        parser = CodexPatch::Parser.new
        expect_raises(CodexPatch::ParseError, /cannot be specified more than once/) do
          parser.parse(patch)
        end
      end

      it "rejects empty environment ID" do
        patch = <<-PATCH
                  *** Begin Patch
                  *** Environment ID:
                  *** Add File: hello.txt
                  +Hello
                  *** End Patch
                  PATCH

        parser = CodexPatch::Parser.new
        expect_raises(CodexPatch::ParseError, /cannot be empty/) do
          parser.parse(patch)
        end
      end
    end

    describe "End Patch handling" do
      it "allows empty lines after END_PATCH_MARKER" do
        patch = <<-PATCH
                  *** Begin Patch
                  *** Add File: hello.txt
                  +Hello
                  *** End Patch


                  PATCH

        parser = CodexPatch::Parser.new
        hunks = parser.parse(patch)

        hunks.size.should eq(1)
      end

      it "rejects non-empty lines after END_PATCH_MARKER" do
        patch = <<-PATCH
                  *** Begin Patch
                  *** Add File: hello.txt
                  +Hello
                  *** End Patch
                  some text
                  PATCH

        parser = CodexPatch::Parser.new
        expect_raises(CodexPatch::ParseError, /must be '.*End Patch'/) do
          parser.parse(patch)
        end
      end
    end

    describe "Error cases" do
      it "raises error if patch does not start with BEGIN_PATCH_MARKER" do
        patch = <<-PATCH
                  *** Add File: hello.txt
                  +Hello
                  *** End Patch
                  PATCH

        parser = CodexPatch::Parser.new
        expect_raises(CodexPatch::ParseError, /first line/) do
          parser.parse(patch)
        end
      end

      it "raises error if patch does not end with END_PATCH_MARKER" do
        patch = <<-PATCH
                  *** Begin Patch
                  *** Add File: hello.txt
                  +Hello
                  PATCH

        parser = CodexPatch::Parser.new
        expect_raises(CodexPatch::ParseError, /must be '.*End Patch'/) do
          parser.parse(patch)
        end
      end

      it "raises error for invalid hunk header" do
        patch = <<-PATCH
                  *** Begin Patch
                  *** Invalid Header: something
                  *** End Patch
                  PATCH

        parser = CodexPatch::Parser.new
        expect_raises(CodexPatch::ParseError, /not a valid hunk header/) do
          parser.parse(patch)
        end
      end

      it "raises error for invalid hunk header after AddFile hunk" do
        patch = <<-PATCH
                  *** Begin Patch
                  *** Add File: hello.txt
                  +Hello
                  This is not valid
                  *** End Patch
                  PATCH

        parser = CodexPatch::Parser.new
        expect_raises(CodexPatch::ParseError, /is not a valid hunk header/) do
          parser.parse(patch)
        end
      end

      it "raises error for Add File line without + prefix" do
        patch = <<-PATCH
                  *** Begin Patch
                  *** Add File: hello.txt
                  no plus
                  *** End Patch
                  PATCH

        parser = CodexPatch::Parser.new
        expect_raises(CodexPatch::ParseError, /is not a valid hunk header/) do
          parser.parse(patch)
        end
      end

      it "raises error for Update hunk line with invalid prefix" do
        patch = <<-PATCH
                  *** Begin Patch
                  *** Update File: file.txt
                  @@ old @@
                  old
                  new without prefix
                  *** End Patch
                  PATCH

        parser = CodexPatch::Parser.new
        expect_raises(CodexPatch::ParseError, /Unexpected line in update hunk/) do
          parser.parse(patch)
        end
      end

      it "raises error for EOF marker on empty update hunk" do
        patch = <<-PATCH
                  *** Begin Patch
                  *** Update File: file.txt
                  *** End of File
                  *** End Patch
                  PATCH

        parser = CodexPatch::Parser.new
        expect_raises(CodexPatch::ParseError, /does not contain any lines/) do
          parser.parse(patch)
        end
      end
    end
  end
end
