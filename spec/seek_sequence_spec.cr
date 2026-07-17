require "./spec_helper"

module CodexPatch
  describe ApplyPatch do
    context "#seek_sequence" do
      describe "test_seek" do
        it "exact match finds sequence" do
          lines = ["foo", "bar", "baz"]
          pattern = ["bar", "baz"]
          ApplyPatch.seek_sequence(lines, pattern, 0, false).should eq(1)
        end

        it "rstrip match ignores trailing whitespace" do
          lines = ["foo      ", "bar\t\t"]
          pattern = ["foo", "bar"]
          ApplyPatch.seek_sequence(lines, pattern, 0, false).should eq(0)
        end

        it "trim match ignores leading and trailing whitespace" do
          lines = ["   foo     ", "   bar\t"]
          pattern = ["foo", "bar"]
          ApplyPatch.seek_sequence(lines, pattern, 0, false).should eq(0)
        end

        it "trim and normalize (unicode) match finds sequence" do
          lines = ["foo", "\u{2011}bar", "\u{201A}baz'"]
          pattern = ["\u{2014}bar", "'baz\u{2018}"]
          ApplyPatch.seek_sequence(lines, pattern, 0, false).should eq(1)
        end

        it "pattern longer than input returns nil" do
          lines = ["just one line"]
          pattern = ["too", "many", "lines"]
          ApplyPatch.seek_sequence(lines, pattern, 0, false).should be_nil
        end

        it "pattern exceeding lines count returns nil" do
          lines = ["a", "b"]
          pattern = ["x", "y", "z", "w"]
          ApplyPatch.seek_sequence(lines, pattern, 0, false).should be_nil
        end

        it "eof mode searches from end of file" do
          lines = ["foo", "bar", "baz"]
          pattern = ["bar", "baz"]
          ApplyPatch.seek_sequence(lines, pattern, 0, true).should eq(1)

          # When eof is true and pattern fits exactly at the end
          lines = ["foo", "bar"]
          pattern = ["foo", "bar"]
          ApplyPatch.seek_sequence(lines, pattern, 0, true).should eq(0)
        end
      end
    end
  end
end
