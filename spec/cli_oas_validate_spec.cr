require "spec"
require "../src/wacli/cli"

describe Wacli::CLI do
  it "returns 0 for valid openapi document" do
    out = IO::Memory.new
    err = IO::Memory.new
    code = Wacli::CLI.run(["oas", "validate", "spec/fixtures/oas2_min.json"], out, err)
    code.should eq(0)
  end

  it "returns 2 for unsupported version (valid JSON)" do
    File.tempfile("wacli_unsupported", ".json") do |f|
      f.print(%({"openapi":"9.9.9","paths":{}}))
      f.flush
      out = IO::Memory.new
      err = IO::Memory.new
      code = Wacli::CLI.run(["oas", "validate", f.path], out, err)
      code.should eq(2)
    end
  end
end
