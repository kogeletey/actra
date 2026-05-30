require "spec"

require "../src/actra/cli"

describe "auth shell" do
  it "prints shell exports for Lefine, Claude SDK, and Codex API auth" do
    stdout = IO::Memory.new
    stderr = IO::Memory.new

    code = Actra::CLI.run(["auth", "shell", "bash"], IO::Memory.new, stdout, stderr)

    code.should eq(0)
    out = stdout.to_s
    out.should contain("LEFINE_TOKEN")
    out.should contain("ANTHROPIC_API_KEY")
    out.should contain("OPENAI_API_KEY")
    out.should contain("ACTRA_DEFAULT_SERVER")
    out.should contain("lefine.pro")
    out.should_not contain("sk-")
    stderr.to_s.should eq("")
  end
end
