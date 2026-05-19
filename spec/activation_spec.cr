require "spec"

require "../src/actra/activation"

describe Actra::Activation do
  it "prints zsh dispatch hooks for @ commands" do
    script = Actra::Activation.script("zsh")
    script.should contain("_actra_dispatch")
    script.should contain("_actra_query")
    script.should contain("command_not_found_handler")
    script.should contain("\\?*) _actra_query")
    script.should contain("function '?' { command actra query")
    script.should contain("function '@' { command actra @")
    script.should contain("function '@?' { command actra @?")
    script.should contain("function '@file' { command actra @file")
    script.should_not contain("/@")
    script.should contain("_actra_complete_at")
    script.should contain("complete at")
    script.should contain("function '@code'")
    script.should contain("@claude")
    script.should contain("@codex")
    script.should contain("actra_auth_status")
    script.should contain("actra dispatch")
  end

  it "prints bash dispatch hooks for @ commands" do
    script = Actra::Activation.script("bash")
    script.should contain("_actra_query")
    script.should contain("command_not_found_handle")
    script.should contain("\\?*) _actra_query")
    script.should contain("?() { command actra query")
    script.should contain("function @ { command actra @")
    script.should contain("function @? { command actra @?")
    script.should contain("@file() { command actra @file")
    script.should_not contain("/@")
    script.should contain("_actra_complete_at")
    script.should contain("complete at")
    script.should contain("alias @code")
    script.should contain("alias @claude")
    script.should contain("alias @codex")
    script.should contain("actra_auth_status")
    script.should contain("actra dispatch")
  end
end
