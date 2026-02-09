require "spec"
require "file_utils"

require "./support/tmpdir"
require "../src/wacli/cli"

private def with_temp_root(&)
  SpecTmpdir.with do |root|
    ENV["WACLI_TEST_ROOT"] = root
    begin
      yield root
    ensure
      ENV.delete("WACLI_TEST_ROOT")
    end
  end
end

describe "wacli render" do
  it "renders a file as a table" do
    with_temp_root do |root|
      p = File.join(root, "in.json")
      File.write(p, %([{"a":1},{"a":2}]))

      stdin = IO::Memory.new
      stdout = IO::Memory.new
      stderr = IO::Memory.new
      Wacli::CLI.run(["render", "--in", p, "--render", "table"], stdin, stdout, stderr).should eq(0)
      stdout.to_s.should contain("a")
      stdout.to_s.should contain("1")
    end
  end
end

