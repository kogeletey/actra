require "spec"
require "file_utils"

require "./support/tmpdir"
require "../src/wacli/cli"
require "../src/wacli/xdg"

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

describe "shell mode" do
  it "prints aliases for explicit tool refs" do
    stdout_io = IO::Memory.new
    stderr_io = IO::Memory.new
    Wacli::CLI.run(["shell", "bash", "example.org"], stdout_io, stderr_io).should eq(0)
    stdout_io.to_s.should contain("alias example.org='wacli example.org'")
  end

  it "prints aliases for installed tools from wa.lock" do
    with_temp_root do |root|
      lock_dir = File.join(root, "config", "wacli")
      FileUtils.mkdir_p(lock_dir)
      File.write(File.join(lock_dir, "wa.lock"), %({
        "fileVersion": 1,
        "ains": { "example.org": { "installPath": "/tmp/x", "source": "https://example.org/openapi.json", "integrity": "x", "openapiVersion": "3.0" } }
      }))

      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new
      Wacli::CLI.run(["shell", "bash", "--installed"], stdout_io, stderr_io).should eq(0)
      stdout_io.to_s.should contain("alias example.org='wacli example.org'")
    end
  end
end
