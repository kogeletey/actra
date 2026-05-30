require "spec"

require "../src/actra/cli"

describe "actra render command" do
  it "is no longer a standalone command" do
    stdout = IO::Memory.new
    stderr = IO::Memory.new

    code = Actra::CLI.run(["render"], IO::Memory.new, stdout, stderr)

    code.should eq(1)
    stderr.to_s.should contain("missing operation tokens")
  end
end
