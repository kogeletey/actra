require "spec"
require "file_utils"

require "./support/tmpdir"
require "../src/actra/cli"
require "../src/actra/xdg"

private def with_temp_root(&)
  SpecTmpdir.with do |root|
    ENV["ACTRA_TEST_ROOT"] = root
    begin
      yield root
    ensure
      ENV.delete("ACTRA_TEST_ROOT")
    end
  end
end

describe "shell mode" do
  it "prints aliases for explicit tool refs" do
    stdin_io = IO::Memory.new
    stdout_io = IO::Memory.new
    stderr_io = IO::Memory.new
    Actra::CLI.run(["shell", "bash", "@example.org"], stdin_io, stdout_io, stderr_io).should eq(0)
    stdout_io.to_s.should contain("alias example.org='actra @example.org'")
    stdout_io.to_s.should contain("alias '?example.org'='actra query @example.org'")
  end

  it "prints aliases for installed tools from actra.lock" do
    with_temp_root do |root|
      lock_dir = File.join(root, "config", "actra")
      FileUtils.mkdir_p(lock_dir)
      File.write(File.join(lock_dir, "actra.lock"), %({
        "fileVersion": 1,
        "ains": { "example.org": { "installPath": "/tmp/x", "source": "https://example.org/openapi.json", "integrity": "x", "openapiVersion": "3.0" } }
      }))

      stdin_io = IO::Memory.new
      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new
      Actra::CLI.run(["shell", "bash", "--installed"], stdin_io, stdout_io, stderr_io).should eq(0)
      stdout_io.to_s.should contain("alias example.org='actra @example.org'")
      stdout_io.to_s.should contain("alias '?example.org'='actra query @example.org'")
    end
  end
end
