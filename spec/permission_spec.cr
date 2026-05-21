require "spec"

require "../src/actra/permission"

describe Actra::PermissionChecker do
  it "parses accept-style permission mode aliases" do
    Actra::PermissionMode.from("accept").should eq(Actra::PermissionMode::AcceptAll)
    Actra::PermissionMode.from("accept-all").should eq(Actra::PermissionMode::AcceptAll)
  end

  it "matches session allow entries against request keys, paths, and commands" do
    Actra::PermissionAllowEntry.new("read", "src/**")
      .matches?(Actra::PermissionRequest.new("read", "src/actra/cli.cr", "src/actra/cli.cr"))
      .should be_true

    Actra::PermissionAllowEntry.new("bash", "make *")
      .matches?(Actra::PermissionRequest.new("bash", "make test", nil, "make test"))
      .should be_true
  end

  it "allows standard read access inside the current workspace" do
    checker = Actra::PermissionChecker.new
    request = Actra::PermissionRequest.new("read", "README.md", "README.md")

    checker.check(request).should eq(Actra::PermissionDecision::Allow)
  end

  it "requires approval for write and shell tools in standard mode" do
    checker = Actra::PermissionChecker.new

    checker.check(Actra::PermissionRequest.new("write", "tmp/out.txt", "tmp/out.txt")).should eq(Actra::PermissionDecision::Ask)
    checker.check(Actra::PermissionRequest.new("bash", "make test", nil, "make test")).should eq(Actra::PermissionDecision::Ask)
  end

  it "requires approval for external tools in standard mode" do
    checker = Actra::PermissionChecker.new

    checker.check(Actra::PermissionRequest.new("external_echo", %(external_echo:{"text":"hello"}), nil, "cat")).should eq(Actra::PermissionDecision::Ask)
  end

  it "records non-interactive ask decisions through a callback" do
    requests = [] of Actra::PermissionRequest
    checker = Actra::PermissionChecker.new(
      Actra::PermissionsConfig.new(Actra::PermissionMode::Restrictive),
      nil,
      nil,
      [] of Actra::PermissionAllowEntry,
      nil,
      IO::Memory.new,
      IO::Memory.new,
      ->(request : Actra::PermissionRequest) { requests << request }
    )

    checker.check(Actra::PermissionRequest.new("write", "tmp/out.txt", "tmp/out.txt")).should eq(Actra::PermissionDecision::Ask)
    requests.size.should eq(1)
    requests.first.tool.should eq("write")
    requests.first.input_key.should eq("tmp/out.txt")
    requests.first.reason.should eq("policy")
    requests.first.count.should eq(1)
  end

  it "applies explicit deny rules before allow rules" do
    config = Actra::PermissionsConfig.new(
      Actra::PermissionMode::Standard,
      false,
      [
        Actra::ToolPermissionConfig.new("read", ["secret.txt"], [] of String, ["secret.txt"]),
      ],
      1
    )
    checker = Actra::PermissionChecker.new(config)
    request = Actra::PermissionRequest.new("read", "secret.txt", "secret.txt")

    checker.check(request).should eq(Actra::PermissionDecision::Deny)
    checker.check(request).should eq(Actra::PermissionDecision::Deny)
  end

  it "applies explicit ask rules before allow and default allow policy" do
    config = Actra::PermissionsConfig.new(
      Actra::PermissionMode::Standard,
      false,
      [
        Actra::ToolPermissionConfig.new("read", ["README.md"], ["README.md"], [] of String),
      ],
      8
    )
    checker = Actra::PermissionChecker.new(config)

    checker.check(Actra::PermissionRequest.new("read", "README.md", "README.md")).should eq(Actra::PermissionDecision::Ask)
  end

  it "reuses session allowlist entries" do
    checker = Actra::PermissionChecker.new(
      Actra::PermissionsConfig.new(Actra::PermissionMode::Restrictive),
      nil,
      nil,
      [Actra::PermissionAllowEntry.new("read", "README.md")]
    )

    checker.check(Actra::PermissionRequest.new("read", "README.md", "README.md")).should eq(Actra::PermissionDecision::Allow)
  end

  it "applies session denylist entries before default policy" do
    checker = Actra::PermissionChecker.new(
      Actra::PermissionsConfig.new(Actra::PermissionMode::Standard),
      nil,
      nil,
      [] of Actra::PermissionAllowEntry,
      nil,
      IO::Memory.new,
      IO::Memory.new,
      nil,
      [Actra::PermissionAllowEntry.new("read", "README.md")]
    )

    checker.check(Actra::PermissionRequest.new("read", "README.md", "README.md")).should eq(Actra::PermissionDecision::Deny)
  end

  it "asks when an identical tool request exceeds the doom-loop threshold" do
    requests = [] of Actra::PermissionRequest
    config = Actra::PermissionsConfig.new(Actra::PermissionMode::Standard, false, [] of Actra::ToolPermissionConfig, 1)
    checker = Actra::PermissionChecker.new(
      config,
      nil,
      nil,
      [] of Actra::PermissionAllowEntry,
      nil,
      IO::Memory.new,
      IO::Memory.new,
      ->(request : Actra::PermissionRequest) { requests << request }
    )
    request = Actra::PermissionRequest.new("read", "README.md", "README.md")

    checker.check(request).should eq(Actra::PermissionDecision::Allow)
    checker.check(request).should eq(Actra::PermissionDecision::Ask)
    requests.first.reason.should eq("doom-loop")
    requests.first.count.should eq(2)
  end
end
