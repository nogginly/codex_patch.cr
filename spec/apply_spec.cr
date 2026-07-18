require "./spec_helper"
require "file_utils"

def with_temp_dir(& : String ->)
  base = File.join(
    Dir.tempdir,
    "apply_patch_test_#{Process.pid}"
  )
  Dir.mkdir_p(base)
  begin
    yield base
  ensure
    FileUtils.rm_rf(base)
  end
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
  policy = CodexPatch::DirAccessPolicy.new(dir)
  apply = CodexPatch::ApplyPatch.new(policy, dir)
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
      +#{content.each_line.join("#{EOL}+")}
      *** End Patch
      PATCH
  )
end

describe CodexPatch do
  describe "ApplyPatch" do
    it "adds a file with contents" do
      with_temp_dir do |dir|
        path = File.join(dir, "new.txt")
        content_text = <<-CONTENT
                          Hello, world!
                          Second line
                          CONTENT
        events = add_file_patch(dir, "new.txt", content_text)
        events.first[:action].should eq CodexPatch::ApplyAction::AddedFile
        File.exists?(path).should be_true
        File.read(path).should eq(<<-LINES)
                                    Hello, world!
                                    Second line

                                    LINES
      end
    end

    it "deletes an existing file" do
      with_temp_dir do |dir|
        del_path = File.join(dir, "to_delete.txt")
        File.write(del_path, <<-LINES)
                                temporary content

                                LINES
        events = delete_file_patch(dir, "to_delete.txt")
        events.first[:action].should eq CodexPatch::ApplyAction::DeletedFile
        File.exists?(del_path).should be_false
      end
    end

    it "updates an existing file" do
      with_temp_dir do |dir|
        path = File.join(dir, "update.txt")
        old_content = <<-OLD
                        old line
                        second line
                        OLD
        old_content.should eq(<<-LINES)
                                old line
                                second line
                                LINES

        File.write(path, old_content)
        events = update_file_patch(dir, "update.txt", <<-LINES)
                                                        -old line
                                                        +new content
                                                        LINES
        events.first[:action].should eq CodexPatch::ApplyAction::UpdatedFile
        new_content = File.read(path)
        new_content.should eq(<<-LINES)
                                new content
                                second line

                                LINES
      end
    end

    it "moves a file during update" do
      with_temp_dir do |dir|
        src_path = File.join(dir, "src.txt")
        dst_path = File.join(dir, "dst.txt")
        File.write(src_path, "original")
        events = update_file_with_move_patch(
          dir, "src.txt", "dst.txt", <<-LINES
                                        -original
                                        +renamed
                                        LINES
        )
        events[0][:action].should eq CodexPatch::ApplyAction::MovedFile
        events[1][:action].should eq CodexPatch::ApplyAction::UpdatedFile
        File.exists?(src_path).should be_false
        File.exists?(dst_path).should be_true
        File.read(dst_path).should eq(<<-LINES)
                                        renamed

                                        LINES
      end
    end

    it "applies multiple change chunks to a single file" do
      with_temp_dir do |dir|
        path = File.join(dir, "multi.txt")
        File.write(path, <<-LINES)
                            foo
                            bar
                            baz
                            qux
                            LINES
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
        File.read(path).should eq(<<-LINES)
                                    foo
                                    BAR
                                    baz
                                    QUX

                                    LINES
      end
    end

    it "applies interleaved additions, deletions, and EOF additions" do
      with_temp_dir do |dir|
        path = File.join(dir, "interleaved.txt")
        File.write(path, <<-LINES)
                            a
                            b
                            c
                            d
                            e
                            f
                            LINES
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
        File.read(path).should eq(<<-LINES)
                                    a
                                    B
                                    c
                                    d
                                    E
                                    f
                                    g

                                    LINES
      end
    end

    it "applies a pure addition chunk followed by a removal" do
      with_temp_dir do |dir|
        path = File.join(dir, "panic.txt")
        File.write(path, <<-LINES)
                            line1
                            line2
                            line3

                            LINES

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
        File.read(path).should eq(expected_text)
      end
    end

    it "handles Unicode dash normalization in context matching" do
      with_temp_dir do |dir|
        path = File.join(dir, "unicode.py")
        File.write(path, "import asyncio        # local import \u{2013} avoids top\u{2011}level dep")

        patch = <<-PATCH
                  *** Update File: unicode.py
                  @@
                  -import asyncio        # local import - avoids top-level dep
                  +import asyncio        # HELLO
                  PATCH
        events = apply_patch_string(dir, wrap_patch(patch))
        events.first[:action].should eq CodexPatch::ApplyAction::UpdatedFile
        File.read(path).should eq(<<-LINES)
                                    import asyncio        # HELLO

                                    LINES
      end
    end
  end
end
