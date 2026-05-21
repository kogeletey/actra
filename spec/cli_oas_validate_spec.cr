require "spec"
require "../src/actra/cli"

describe Actra::CLI do
  it "returns 0 for valid openapi document" do
    stdin_io = IO::Memory.new
    stdout_io = IO::Memory.new
    stderr_io = IO::Memory.new
    code = Actra::CLI.run(["oas", "validate", "spec/fixtures/oas2_min.json"], stdin_io, stdout_io, stderr_io)
    code.should eq(0)
  end

  it "returns 2 for unsupported version (valid JSON)" do
    File.tempfile("actra_unsupported", ".json") do |f|
      f.print(%({"openapi":"9.9.9","paths":{}}))
      f.flush
      stdin_io = IO::Memory.new
      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new
      code = Actra::CLI.run(["oas", "validate", f.path], stdin_io, stdout_io, stderr_io)
      code.should eq(2)
    end
  end
end
