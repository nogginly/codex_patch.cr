require "./spec_helper"
require "file_utils"

def create_temp_dir
  pid = Process.pid
  time = Time.local.to_unix.to_s
  base = File.join(
    Dir.tempdir,
    "apply_patch_test_#{pid}_#{time}"
  )
  Dir.mkdir_p(base)
  base
end

def cleanup_temp_dir(dir)
  FileUtils.rm_rf(dir)
end

def mktmpdir(& : String ->)
  base = create_temp_dir
  yield base
ensure
  cleanup_temp_dir(base)
end

def wrap_patch(body : String)
  <<-PATCH
    *** Begin Patch
    #{body}
    *** End Patch
    PATCH
end

def apply_patch_string(dir : String, patch : String) : Array(CodexPatch::ApplyEvent)
  evs = [] of CodexPatch::ApplyEvent
  apply = CodexPatch::ApplyPatch.new(dir)
  apply.apply(IO::Memory.new(patch)) { |ev| evs << ev }
  evs
end

def update_file_patch(dir : String, filename : String, chunk_body : String)
  apply_patch_string(
    dir,
    <<-PATCH
      *** Begin Patch
      *** Update File: #{filename}
      #{chunk_body.rstrip}
      *** End Patch
      PATCH
  )
end

def update_file_with_move_patch(
  dir : String, src : String, dst : String, chunk_body : String,
)
  apply_patch_string(
    dir,
    <<-PATCH
      *** Begin Patch
      *** Update File: #{src}
      *** Move to: #{dst}
      #{chunk_body}
      *** End Patch
      PATCH
  )
end

def delete_file_patch(dir : String, filename : String)
  apply_patch_string(dir, <<-PATCH
                            *** Begin Patch
                            *** Delete File: #{filename}
                            *** End Patch
                            PATCH
  )
end

def add_file_patch(dir : String, filename : String, content : String)
  apply_patch_string(
    dir,
    <<-PATCH
      *** Begin Patch
      *** Add File: #{filename}
      +#{content.each_line.join("\n+")}
      *** End Patch
      PATCH
  )
end

describe CodexPatch do
  describe "ApplyPatch" do
    it "adds a file with contents" do
      dir = create_temp_dir
      begin
        path = File.join(dir, "new.txt")
        content_text = <<-CONTENT
Hello, world!
Second line
CONTENT
        events = add_file_patch(dir, "new.txt", content_text)
        events.first[:action].should eq CodexPatch::ApplyAction::AddedFile
        File.exists?(path).should be_true
        File.read(path).should eq("Hello, world!\nSecond line\n")
      ensure
        cleanup_temp_dir(dir)
      end
    end

    it "deletes an existing file" do
      dir = create_temp_dir
      begin
        del_path = File.join(dir, "to_delete.txt")
        File.write(del_path, "temporary content\n")
        events = delete_file_patch(dir, "to_delete.txt")
        events.first[:action].should eq CodexPatch::ApplyAction::DeletedFile
        File.exists?(del_path).should be_false
      ensure
        cleanup_temp_dir(dir)
      end
    end

    it "updates an existing file" do
      dir = create_temp_dir
      begin
        path = File.join(dir, "update.txt")
        old_content = <<-OLD
                        old line
                        second line
                        OLD
        old_content.should eq("old line\nsecond line")

        File.write(path, old_content)
        events = update_file_patch(dir, "update.txt", "-old line\n+new content\n")
        events.first[:action].should eq CodexPatch::ApplyAction::UpdatedFile
        new_content = File.read(path)
        new_content.should eq("new content\nsecond line\n")
      ensure
        cleanup_temp_dir(dir)
      end
    end

    it "moves a file during update" do
      dir = create_temp_dir
      begin
        src_path = File.join(dir, "src.txt")
        dst_path = File.join(dir, "dst.txt")
        File.write(src_path, "original\n")
        events = update_file_with_move_patch(
          dir, "src.txt", "dst.txt", "-original\n+renamed\n"
        )
        events[0][:action].should eq CodexPatch::ApplyAction::MovedFile
        events[1][:action].should eq CodexPatch::ApplyAction::UpdatedFile
        File.exists?(src_path).should be_false
        File.exists?(dst_path).should be_true
        File.read(dst_path).should eq("renamed\n")
      ensure
        cleanup_temp_dir(dir)
      end
    end

    it "applies multiple change chunks to a single file" do
      dir = create_temp_dir
      begin
        path = File.join(dir, "multi.txt")
        File.write(path, "foo\nbar\nbaz\nqux\n")
        chunk = <<-CHUNK
                  @@
                   foo
                  -bar
                  +BAR
                  @@
                   baz
                  -qux
                  +QUX
                  CHUNK
        events = update_file_patch(dir, "multi.txt", chunk)
        events.size.should eq(1)
        File.read(path).should eq("foo\nBAR\nbaz\nQUX\n")
      ensure
        cleanup_temp_dir(dir)
      end
    end

    it "applies interleaved additions, deletions, and EOF additions" do
      dir = create_temp_dir
      begin
        path = File.join(dir, "interleaved.txt")
        File.write(path, "a\nb\nc\nd\ne\nf\n")
        chunk = <<-CHUNK
                  @@
                   a
                  -b
                  +B
                  @@
                   c
                   d
                  -e
                  +E
                  @@
                   f
                  +g
                  *** End of File
                  CHUNK
        events = update_file_patch(dir, "interleaved.txt", chunk)
        events.size.should eq(1)
        File.read(path).should eq("a\nB\nc\nd\nE\nf\ng\n")
      ensure
        cleanup_temp_dir(dir)
      end
    end

    it "applies a pure addition chunk followed by a removal" do
      dir = create_temp_dir
      begin
        path = File.join(dir, "panic.txt")
        File.write(path, "line1\nline2\nline3\n")
        chunk = <<-CHUNK
                  @@
                  +after-context
                  +second-line
                  @@
                   line1
                  -line2
                  -line3
                  +line2-replacement
                  CHUNK
        events = update_file_patch(dir, "panic.txt", chunk)
        events.size.should eq(1)
        expected_text = <<-EXPECTED
                          line1
                          line2-replacement
                          after-context
                          second-line
                          EXPECTED
        File.read(path).should eq(expected_text + "\n")
      ensure
        cleanup_temp_dir(dir)
      end
    end

    it "handles Unicode dash normalization in context matching" do
      dir = create_temp_dir
      begin
        path = File.join(dir, "unicode.py")
        File.write(path, "import asyncio        # local import \u{2013} avoids top\u{2011}level dep\n")

        patch = <<-PATCH
                  *** Update File: unicode.py
                  @@
                  -import asyncio        # local import - avoids top-level dep
                  +import asyncio        # HELLO
                  PATCH
        events = apply_patch_string(dir, wrap_patch(patch))
        events.first[:action].should eq CodexPatch::ApplyAction::UpdatedFile
        File.read(path).should eq("import asyncio        # HELLO\n")
      ensure
        cleanup_temp_dir(dir)
      end
    end
  end
end
