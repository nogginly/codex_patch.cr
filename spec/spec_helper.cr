require "spec"
require "../src/codex_patch"

# Restrict access to given directory
class DirAccessPolicy
  include CodexPatch::AccessPolicy

  def initialize(@base : String)
  end

  def authorized?(path : String, to : Op) : Bool
    File.expand_path(path).starts_with?(@base)
  end
end
