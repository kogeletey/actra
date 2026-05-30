require "spec"

require "../src/actra/agent_tool"

describe Actra::ToolRegistry do
  it "returns visible permission failures for denied built-in tools" do
    checker = Actra::PermissionChecker.new(Actra::PermissionsConfig.new(Actra::PermissionMode::Restrictive))
    registry = Actra::ToolRegistry.default(true, [] of Actra::ToolSpec, nil, checker)
    call = Actra::ToolCall.new("call_1", "write", JSON.parse(%({"path":"tmp/out.txt","content":"x"})))

    registry.execute(call).should contain("permission required for tool write")
  end

  it "returns visible permission failures for denied extension tools" do
    config = Actra::PermissionsConfig.new(
      Actra::PermissionMode::Standard,
      false,
      [
        Actra::ToolPermissionConfig.new("external_echo", [] of String, [] of String, ["external_echo:*"]),
      ],
      8
    )
    checker = Actra::PermissionChecker.new(config)
    tool = Actra::ToolSpec.new("external_echo", "Echo externally", JSON.parse(%({"type":"object"})), "cat", false)
    registry = Actra::ToolRegistry.default(false, [tool], nil, checker)
    call = Actra::ToolCall.new("call_1", "external_echo", JSON.parse(%({"text":"hello"})))

    registry.execute(call).should contain("permission denied for tool external_echo")
  end

  it "returns a clear sandbox failure when bwrap is requested but unavailable" do
    if Process.find_executable("bwrap")
      true.should be_true
    else
      checker = Actra::PermissionChecker.new(
        Actra::PermissionsConfig.default,
        Actra::PermissionMode::Yolo,
        true
      )
      registry = Actra::ToolRegistry.default(true, [] of Actra::ToolSpec, nil, checker)
      call = Actra::ToolCall.new("call_1", "bash", JSON.parse(%({"command":"printf ok"})))

      registry.execute(call).should contain("sandbox requested but bwrap is not installed")
    end
  end
end
