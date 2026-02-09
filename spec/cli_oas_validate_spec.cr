require "spec"
require "../src/wacli/cli"

describe Wacli::CLI do
  it "returns 0 for valid openapi document" do
    stdout_io = IO::Memory.new
    stderr_io = IO::Memory.new
    code = Wacli::CLI.run(["oas", "validate", "spec/fixtures/oas2_min.json"], stdout_io, stderr_io)
    code.should eq(0)
  end

  it "returns 2 for unsupported version (valid JSON)" do
    File.tempfile("wacli_unsupported", ".json") do |f|
      f.print(%({"openapi":"9.9.9","paths":{}}))
      f.flush
      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new
      code = Wacli::CLI.run(["oas", "validate", f.path], stdout_io, stderr_io)
      code.should eq(2)
    end
  end
end
