require "spec"
require "http/server"
require "socket"
require "file_utils"

require "./support/tmpdir"
require "../src/actra/cli"
require "../src/actra/ai_provider"
require "../src/actra/config"
require "../src/actra/xdg"

private def start_ai_server(captured : Array(String), response : String = %({"output_text":"provider text"})) : Tuple(String, HTTP::Server)
  server = HTTP::Server.new do |ctx|
    captured << ctx.request.path
    captured << ctx.request.body.try(&.gets_to_end).to_s
    ctx.response.content_type = "application/json"
    ctx.response.print response
  end
  addr = server.bind_tcp("127.0.0.1", 0)
  spawn { server.listen }
  {"http://127.0.0.1:#{addr.port}", server}
end

private def start_sequence_ai_server(captured : Array(String), responses : Array(String)) : Tuple(String, HTTP::Server)
  count = 0
  server = HTTP::Server.new do |ctx|
    captured << ctx.request.path
    captured << ctx.request.body.try(&.gets_to_end).to_s
    ctx.response.content_type = "application/json"
    ctx.response.print responses[{count, responses.size - 1}.min]
    count += 1
  end
  addr = server.bind_tcp("127.0.0.1", 0)
  spawn { server.listen }
  {"http://127.0.0.1:#{addr.port}", server}
end

private def with_agent_root(base_url : String, api : String = "openai-responses", provider_name : String = "local", &)
  SpecTmpdir.with do |root|
    ENV["ACTRA_TEST_ROOT"] = root
    FileUtils.mkdir_p(Actra::Xdg.config_dir)
    File.write(Actra::Xdg.config_path, %(
      base do
        default_provider = "#{provider_name}"
        default_model = "test-model"
        session_dir = "$HOME/.cache/actra/test-sessions"
      end

      provider "#{provider_name}" do
        api = "#{api}"
        base_url = "#{base_url}"
        auth_header = false
        default_model = "test-model"
      end
    ))
    begin
      yield root
    ensure
      ENV.delete("ACTRA_TEST_ROOT")
    end
  end
end

describe "agent provider modes" do
  it "delivers agent prompts through ForgeFed providers" do
    captured = [] of String
    base, server = start_ai_server(captured, "accepted")
    begin
      SpecTmpdir.with do |root|
        ENV["ACTRA_TEST_ROOT"] = root
        FileUtils.mkdir_p(Actra::Xdg.config_dir)
        File.write(Actra::Xdg.config_path, %(
          base do
            default_provider = "remote-code"
            default_server = "local"
            session_dir = "$HOME/.cache/actra/test-sessions"
          end

          server "local" do
            base_url = "#{base}"
            actor_id = "#{base}/actor/shell"
            inbox = "/inbox"

            actor "code" do
              command = "@code"
              inbox = "/inbox/code"
              outbox = "/outbox/code"
              work_type = "code"
            end
          end

          provider "remote-code" do
            api = "forgefed"
            server = "local"
            actor = "code"
            auth_header = false
          end
        ))

        stdout = IO::Memory.new
        stderr = IO::Memory.new
        code = Actra::CLI.run(["agent", "--no-session", "ship it"], IO::Memory.new, stdout, stderr)

        code.should eq(0)
        stdout.to_s.should eq("accepted\n")
        captured[0].should eq("/inbox/code")
        activity = JSON.parse(captured[1])
        activity["type"].as_s.should eq("Create")
        activity["object"]["type"].as_s.should eq("Ticket")
        activity["object"]["content"].as_s.should eq("ship it")
      ensure
        ENV.delete("ACTRA_TEST_ROOT")
      end
    ensure
      server.close
    end
  end

  it "routes configured at actions through their agent provider defaults" do
    captured = [] of String
    base, server = start_ai_server(captured)
    begin
      with_agent_root(base) do
        File.write(Actra::Xdg.config_path, %(
          base do
            default_provider = "openai"
            default_model = "default-model"
            session_dir = "$HOME/.cache/actra/test-sessions"
          end

          provider "fast-local" do
            api = "openai-responses"
            base_url = "#{base}"
            auth_header = false
            default_model = "fast-model"
          end

          at do
            action "review" do
              kind = "agent"
              label = "Review"
              provider = "fast-local"
              model = "fast-model"
              prompt_modes = ["review"]
            end
          end
        ))

        stdout = IO::Memory.new
        stderr = IO::Memory.new
        code = Actra::CLI.run(["@", "--action", "review", "check this"], IO::Memory.new, stdout, stderr)

        code.should eq(0)
        stdout.to_s.should eq("provider text\n")
        captured[0].should eq("/responses")
        payload = JSON.parse(captured[1])
        payload["model"].as_s.should eq("fast-model")
        payload["input"].as_s.should contain("check this")
      end
    ensure
      server.close
    end
  end

  it "prints help without entering agent/session mode" do
    stdout = IO::Memory.new
    stderr = IO::Memory.new
    code = Actra::CLI.run(["--help"], IO::Memory.new, stdout, stderr)

    code.should eq(1)
    stdout.to_s.should contain("actra agent")
    stdout.to_s.should contain("--permission-mode standard|restrictive|accept|accept-all|yolo")
    stderr.to_s.should eq("")
  end

  it "lists configured models without calling a provider" do
    with_agent_root("http://127.0.0.1:9") do
      stdout = IO::Memory.new
      stderr = IO::Memory.new
      code = Actra::CLI.run(["--list-models"], IO::Memory.new, stdout, stderr)

      code.should eq(0)
      stdout.to_s.should contain("local/test-model")
    end
  end

  it "uses @auto@lefine.pro as the default model when no model is configured" do
    cfg = Actra::Config.default
    request = Actra::AiProvider.build_request(cfg, nil, nil, "hello", nil)

    request.model.should eq("@auto@lefine.pro")
    request.payload["model"].as_s.should eq("@auto@lefine.pro")
  end

  it "lists live OpenAI-compatible local provider models when available" do
    captured = [] of String
    base, server = start_ai_server(captured, %({"data":[{"id":"qwen2.5-coder:7b"},{"id":"llama3.1:8b"}]}))
    begin
      with_agent_root(base, "openai-chat", "ollama") do
        stdout = IO::Memory.new
        stderr = IO::Memory.new
        code = Actra::CLI.run(["--list-models", "ollama"], IO::Memory.new, stdout, stderr)

        code.should eq(0)
        captured[0].should eq("/models")
        stdout.to_s.should contain("ollama/qwen2.5-coder:7b")
        stdout.to_s.should contain("ollama/llama3.1:8b")
      end
    ensure
      server.close
    end
  end

  it "lists built-in zerostack-style prompt modes without calling a provider" do
    with_agent_root("http://127.0.0.1:9") do
      stdout = IO::Memory.new
      stderr = IO::Memory.new
      code = Actra::CLI.run(["--list-prompts"], IO::Memory.new, stdout, stderr)

      code.should eq(0)
      stdout.to_s.should contain("code")
      stdout.to_s.should contain("review-security")
      stdout.to_s.should contain("write-prompt")
    end
  end

  it "builds OpenAI Responses payloads and prints provider text" do
    captured = [] of String
    base, server = start_ai_server(captured)
    begin
      with_agent_root(base) do
        stdout = IO::Memory.new
        stderr = IO::Memory.new
        code = Actra::CLI.run(["-p", "--no-session", "hello"], IO::Memory.new, stdout, stderr)

        code.should eq(0)
        stdout.to_s.should eq("provider text\n")
        captured[0].should eq("/responses")
        body = JSON.parse(captured[1])
        body["model"].as_s.should eq("test-model")
        body["input"].as_s.should eq("hello")
      end
    ensure
      server.close
    end
  end

  it "sends plain multi-word text to the default provider" do
    captured = [] of String
    base, server = start_ai_server(captured)
    begin
      with_agent_root(base) do
        stdout = IO::Memory.new
        stderr = IO::Memory.new
        code = Actra::CLI.run(["hello", "world"], IO::Memory.new, stdout, stderr)

        code.should eq(0)
        JSON.parse(captured[1])["input"].as_s.should eq("hello world")
      end
    ensure
      server.close
    end
  end

  it "injects selected prompt mode instructions into agent requests" do
    captured = [] of String
    base, server = start_ai_server(captured)
    begin
      with_agent_root(base) do
        stdout = IO::Memory.new
        stderr = IO::Memory.new
        code = Actra::CLI.run(["agent", "--no-session", "--prompt", "review", "hello"], IO::Memory.new, stdout, stderr)

        code.should eq(0)
        body = JSON.parse(captured[1])
        body["instructions"].as_s.should contain("Code Review Mode")
        body["input"].as_s.should eq("hello")
      end
    ensure
      server.close
    end
  end

  it "builds OpenAI Chat Completions payloads" do
    captured = [] of String
    base, server = start_ai_server(captured, %({"choices":[{"message":{"content":"chat text"}}]}))
    begin
      with_agent_root(base, "openai-completions") do
        stdout = IO::Memory.new
        stderr = IO::Memory.new
        code = Actra::CLI.run(["agent", "--no-session", "--system-prompt", "sys", "hello"], IO::Memory.new, stdout, stderr)

        code.should eq(0)
        stdout.to_s.should eq("chat text\n")
        captured[0].should eq("/chat/completions")
        messages = JSON.parse(captured[1])["messages"].as_a
        messages[0]["role"].as_s.should eq("system")
        messages[1]["content"].as_s.should eq("hello")
      end
    ensure
      server.close
    end
  end

  it "ships local Ollama and llama.cpp provider presets" do
    cfg = Actra::Config.default

    ollama = cfg.providers["ollama"]
    ollama.api.should eq("openai-chat")
    ollama.base_url.should eq("http://127.0.0.1:11434/v1")
    ollama.auth_header.should be_false
    ollama.default_model.should eq("llama3.1:8b")

    llamacpp = cfg.providers["llama.cpp"]
    llamacpp.api.should eq("openai-chat")
    llamacpp.base_url.should eq("http://127.0.0.1:8080/v1")
    llamacpp.auth_header.should be_false
    llamacpp.default_model.should eq("local")

    alias_provider = cfg.providers["llamacpp"]
    alias_provider.api.should eq("openai-chat")
    alias_provider.base_url.should eq("http://127.0.0.1:8080/v1")
    alias_provider.auth_header.should be_false
    alias_provider.default_model.should eq("local")
  end

  it "routes local provider presets through chat completions payloads" do
    {"ollama", "llama.cpp", "llamacpp"}.each do |provider_name|
      captured = [] of String
      base, server = start_ai_server(captured, %({"choices":[{"message":{"content":"local chat text"}}]}))
      begin
        with_agent_root(base, "openai-chat", provider_name) do
          stdout = IO::Memory.new
          stderr = IO::Memory.new
          code = Actra::CLI.run(["agent", "--no-session", "--provider", provider_name, "--model", "local-test-model", "hello local"], IO::Memory.new, stdout, stderr)

          code.should eq(0)
          stdout.to_s.should eq("local chat text\n")
          captured[0].should eq("/chat/completions")
          body = JSON.parse(captured[1])
          body["model"].as_s.should eq("local-test-model")
          messages = body["messages"].as_a
          messages.last["content"].as_s.should eq("hello local")
        end
      ensure
        server.close
      end
    end
  end

  it "runs a tool call and sends tool results back to the provider" do
    captured = [] of String
    first = {
      "output" => [
        {
          "type"      => "function_call",
          "call_id"   => "call_1",
          "name"      => "read",
          "arguments" => {"path" => "tool-input.txt"}.to_json,
        },
      ],
    }.to_json
    base, server = start_sequence_ai_server(captured, [first, %({"output_text":"final with tool"})])
    begin
      with_agent_root(base) do
        File.write("tool-input.txt", "tool file text")
        stdout = IO::Memory.new
        stderr = IO::Memory.new
        code = Actra::CLI.run(["agent", "--no-session", "read the file"], IO::Memory.new, stdout, stderr)

        code.should eq(0)
        stdout.to_s.should eq("final with tool\n")
        first_payload = JSON.parse(captured[1])
        first_payload["tools"].as_a.any? { |tool| tool["name"]?.try(&.as_s?) == "read" }.should be_true
        follow_up_payload = JSON.parse(captured[3])
        follow_up_payload["input"].as_s.should contain("tool file text")
      ensure
        File.delete("tool-input.txt") if File.exists?("tool-input.txt")
      end
    ensure
      server.close
    end
  end

  it "uses session permission allowlist in restrictive mode" do
    captured = [] of String
    first = {
      "output" => [
        {
          "type"      => "function_call",
          "call_id"   => "call_1",
          "name"      => "read",
          "arguments" => {"path" => "tool-input.txt"}.to_json,
        },
      ],
    }.to_json
    base, server = start_sequence_ai_server(captured, [first, %({"output_text":"final allowed tool"})])
    begin
      with_agent_root(base) do
        session = Actra::AgentSession.open(Actra::Config.load.session_dir, "allowed")
        session.append_permission_allow("read", "tool-input.txt")
        File.write("tool-input.txt", "tool file text")

        stdout = IO::Memory.new
        stderr = IO::Memory.new
        code = Actra::CLI.run(["agent", "--session", "allowed", "--restrictive", "read the file"], IO::Memory.new, stdout, stderr)

        code.should eq(0)
        stdout.to_s.should eq("final allowed tool\n")
        follow_up_payload = JSON.parse(captured[3])
        follow_up_payload["input"].as_s.should contain("tool file text")
      ensure
        File.delete("tool-input.txt") if File.exists?("tool-input.txt")
      end
    ensure
      server.close
    end
  end

  it "emits Pi-like JSON events and persists a session" do
    captured = [] of String
    base, server = start_ai_server(captured)
    begin
      with_agent_root(base) do
        stdout = IO::Memory.new
        stderr = IO::Memory.new
        code = Actra::CLI.run(["--mode", "json", "hello"], IO::Memory.new, stdout, stderr)

        code.should eq(0)
        lines = stdout.to_s.lines.map { |line| JSON.parse(line) }
        lines[0]["type"].as_s.should eq("session")
        lines[0]["permissions"]["mode"].as_s.should eq("standard")
        lines[0]["permissions"]["mode_source"].as_s.should eq("config")
        lines[0]["permissions"]["doom_loop_threshold"].as_i.should eq(8)
        lines.any? { |event| event["type"]?.try(&.as_s?) == "message_update" && event["content"].as_s == "provider text" }.should be_true
        session_id = lines[0]["id"].as_s
        File.exists?(File.join(Actra::Config.load.session_dir, "#{session_id}.jsonl")).should be_true
      end
    ensure
      server.close
    end
  end

  it "handles a minimal JSONL RPC prompt" do
    captured = [] of String
    base, server = start_ai_server(captured)
    begin
      with_agent_root(base) do
        input = IO::Memory.new(%({"id":"1","type":"prompt","prompt":"hello"}\n))
        stdout = IO::Memory.new
        stderr = IO::Memory.new
        code = Actra::CLI.run(["--mode", "rpc"], input, stdout, stderr)

        code.should eq(0)
        lines = stdout.to_s.lines.map { |line| JSON.parse(line) }
        lines[0]["type"].as_s.should eq("ready")
        lines[1]["type"].as_s.should eq("response")
        lines[1]["text"].as_s.should eq("provider text")
      end
    ensure
      server.close
    end
  end

  it "manages permission allowlist over JSONL RPC" do
    with_agent_root("http://127.0.0.1:9") do
      input = IO::Memory.new(%({"id":"1","type":"permission_allow","tool":"read","pattern":"tool-input.txt"}\n{"id":"2","type":"permissions"}\n{"id":"3","type":"permission_mode","mode":"accept-all"}\n{"id":"4","type":"permission_revoke","tool":"read","pattern":"tool-input.txt"}\n{"id":"5","type":"permissions"}\n{"id":"6","type":"permission_deny","tool":"read","pattern":"tool-input.txt"}\n))
      stdout = IO::Memory.new
      stderr = IO::Memory.new
      code = Actra::CLI.run(["--mode", "rpc", "--restrictive"], input, stdout, stderr)

      code.should eq(0)
      lines = stdout.to_s.lines.map { |line| JSON.parse(line) }
      session_id = lines[0]["session_id"].as_s
      lines[1]["command"].as_s.should eq("permission_allow")
      lines[1]["data"]["allowlist"].as_a.first["tool"].as_s.should eq("read")
      lines[2]["command"].as_s.should eq("permissions")
      lines[2]["data"]["mode"].as_s.should eq("restrictive")
      lines[2]["data"]["mode_source"].as_s.should eq("override")
      lines[2]["data"]["doom_loop_threshold"].as_i.should eq(8)
      lines[2]["data"]["allowlist"].as_a.first["pattern"].as_s.should eq("tool-input.txt")
      lines[3]["command"].as_s.should eq("permission_mode")
      lines[3]["data"]["mode"].as_s.should eq("accept-all")
      lines[3]["data"]["mode_source"].as_s.should eq("override")
      lines[4]["command"].as_s.should eq("permission_revoke")
      lines[4]["data"]["allowlist"].as_a.empty?.should be_true
      lines[5]["command"].as_s.should eq("permissions")
      lines[5]["data"]["allowlist"].as_a.empty?.should be_true
      lines[6]["command"].as_s.should eq("permission_deny")
      lines[6]["data"]["denials"].as_a.first["pattern"].as_s.should eq("tool-input.txt")
      lines[6]["data"]["decisions"].as_a.first["decision"].as_s.should eq("deny")

      session = Actra::AgentSession.existing(Actra::Config.load.session_dir, session_id)
      session.permission_allowlist.empty?.should be_true
      session.permission_denials.first.pattern.should eq("tool-input.txt")
    end
  end

  it "accepts generic permission mode CLI flag aliases" do
    with_agent_root("http://127.0.0.1:9") do
      input = IO::Memory.new(%({"id":"1","type":"permissions"}\n))
      stdout = IO::Memory.new
      stderr = IO::Memory.new
      code = Actra::CLI.run(["--mode", "rpc", "--permission-mode", "accept"], input, stdout, stderr)

      code.should eq(0)
      lines = stdout.to_s.lines.map { |line| JSON.parse(line) }
      lines[1]["data"]["mode"].as_s.should eq("accept-all")
    end
  end

  it "prints permission state without calling a provider" do
    with_agent_root("http://127.0.0.1:9") do
      stdout = IO::Memory.new
      stderr = IO::Memory.new
      code = Actra::CLI.run(["--permission-state", "--permission-mode", "accept"], IO::Memory.new, stdout, stderr)

      code.should eq(0)
      state = JSON.parse(stdout.to_s)
      state["session_id"].as_s.empty?.should be_false
      state["mode"].as_s.should eq("accept-all")
      state["mode_source"].as_s.should eq("override")
      state["requests"].as_a.empty?.should be_true
    end
  end

  it "mutates session permissions from direct CLI flags without calling a provider" do
    with_agent_root("http://127.0.0.1:9") do
      stdout = IO::Memory.new
      stderr = IO::Memory.new
      code = Actra::CLI.run(["--session", "direct", "--permission-allow", "read:README.md", "--permission-deny", "bash:make *"], IO::Memory.new, stdout, stderr)

      code.should eq(0)
      state = JSON.parse(stdout.to_s)
      state["session_id"].as_s.should eq("direct")
      state["allowlist"].as_a.first["pattern"].as_s.should eq("README.md")
      state["denials"].as_a.first["pattern"].as_s.should eq("make *")

      revoke_stdout = IO::Memory.new
      revoke_stderr = IO::Memory.new
      revoke_code = Actra::CLI.run(["--session", "direct", "--permission-revoke", "read:README.md"], IO::Memory.new, revoke_stdout, revoke_stderr)

      revoke_code.should eq(0)
      revoked = JSON.parse(revoke_stdout.to_s)
      revoked["allowlist"].as_a.empty?.should be_true
      revoked["denials"].as_a.first["tool"].as_s.should eq("bash")

      clear_stdout = IO::Memory.new
      clear_stderr = IO::Memory.new
      clear_code = Actra::CLI.run(["--session", "direct", "--permission-clear"], IO::Memory.new, clear_stdout, clear_stderr)

      clear_code.should eq(0)
      cleared = JSON.parse(clear_stdout.to_s)
      cleared["decisions"].as_a.empty?.should be_true
    end
  end

  it "lets extension hooks rewrite provider request payloads" do
    captured = [] of String
    base, server = start_ai_server(captured)
    begin
      with_agent_root(base) do |root|
        script = File.join(root, "rewrite.sh")
        File.write(script, %(#!/bin/sh\ncat >/dev/null\nprintf '{"model":"test-model","input":"rewritten"}'\n))
        File.write(Actra::Xdg.config_path, %(
          base do
            default_provider = "local"
            default_model = "test-model"
            session_dir = "$HOME/.cache/actra/test-sessions"
          end

          provider "local" do
            api = "openai-responses"
            base_url = "#{base}"
            auth_header = false
            default_model = "test-model"
          end

          extension "rewrite" do
            command = "sh #{script}"
            events = ["before_provider_request"]
          end
        ))

        stdout = IO::Memory.new
        stderr = IO::Memory.new
        code = Actra::CLI.run(["agent", "--no-session", "hello"], IO::Memory.new, stdout, stderr)

        code.should eq(0)
        JSON.parse(captured[1])["input"].as_s.should eq("rewritten")
      end
    ensure
      server.close
    end
  end

  it "loads explicit extension hooks from --extension" do
    captured = [] of String
    base, server = start_ai_server(captured)
    begin
      with_agent_root(base) do |root|
        script = File.join(root, "rewrite.sh")
        File.write(script, %(#!/bin/sh\ncat >/dev/null\nprintf '{"model":"test-model","input":"explicit"}'\n))

        stdout = IO::Memory.new
        stderr = IO::Memory.new
        code = Actra::CLI.run(["agent", "--no-session", "--extension", script, "hello"], IO::Memory.new, stdout, stderr)

        stderr.to_s.should eq("")
        code.should eq(0)
        JSON.parse(captured[1])["input"].as_s.should eq("explicit")
      end
    ensure
      server.close
    end
  end

  it "loads Crystal extension hooks with a Pi-like API" do
    captured = [] of String
    base, server = start_ai_server(captured)
    begin
      with_agent_root(base) do |root|
        script = File.join(root, "rewrite.cr")
        File.write(script, %(
          require "actra/extension_api"

          Actra::Extension.run do |pi|
            pi.on("before_provider_request") do |_payload|
              JSON.parse({"model" => "test-model", "input" => "crystal hook"}.to_json)
            end
          end
        ))

        stdout = IO::Memory.new
        stderr = IO::Memory.new
        code = Actra::CLI.run(["agent", "--no-session", "--extension", script, "hello"], IO::Memory.new, stdout, stderr)

        stderr.to_s.should eq("")
        code.should eq(0)
        JSON.parse(captured[1])["input"].as_s.should eq("crystal hook")
      end
    ensure
      server.close
    end
  end

  it "registers Crystal extension tools with a Pi-like API" do
    captured = [] of String
    first = {
      "output" => [
        {
          "type"      => "function_call",
          "call_id"   => "call_1",
          "name"      => "crystal_echo",
          "arguments" => {"text" => "hello from tool"}.to_json,
        },
      ],
    }.to_json
    base, server = start_sequence_ai_server(captured, [first, %({"output_text":"final crystal tool"})])
    begin
      with_agent_root(base) do |root|
        script = File.join(root, "tool.cr")
        File.write(script, %(
          require "actra/extension_api"

          Actra::Extension.run do |pi|
            schema = JSON.parse({"type" => "object", "properties" => {"text" => {"type" => "string"}}}.to_json)
            pi.register_tool("crystal_echo", "Echo text from Crystal", schema) do |args|
              "crystal says: \#{args["text"].as_s}"
            end
          end
        ))

        stdout = IO::Memory.new
        stderr = IO::Memory.new
        code = Actra::CLI.run(["agent", "--no-session", "--accept-all", "--extension", script, "use crystal tool"], IO::Memory.new, stdout, stderr)

        stderr.to_s.should eq("")
        code.should eq(0)
        first_payload = JSON.parse(captured[1])
        first_payload["tools"].as_a.any? { |tool| tool["name"]?.try(&.as_s?) == "crystal_echo" }.should be_true
        follow_up_payload = JSON.parse(captured[3])
        follow_up_payload["input"].as_s.should contain("crystal says: hello from tool")
      end
    ensure
      server.close
    end
  end

  it "exports a saved session to HTML" do
    captured = [] of String
    base, server = start_ai_server(captured)
    begin
      with_agent_root(base) do |root|
        stdout = IO::Memory.new
        stderr = IO::Memory.new
        code = Actra::CLI.run(["--mode", "json", "hello"], IO::Memory.new, stdout, stderr)
        code.should eq(0)
        session_id = JSON.parse(stdout.to_s.lines.first)["id"].as_s

        export_path = File.join(root, "session.html")
        export_stdout = IO::Memory.new
        export_stderr = IO::Memory.new
        export_code = Actra::CLI.run(["--export", session_id, export_path], IO::Memory.new, export_stdout, export_stderr)

        export_code.should eq(0)
        File.read(export_path).should contain("provider text")
      end
    ensure
      server.close
    end
  end

  it "sends bare executable-looking text to the default provider" do
    captured = [] of String
    base, server = start_ai_server(captured)
    begin
      with_agent_root(base) do
        stdout = IO::Memory.new
        stderr = IO::Memory.new
        code = Actra::CLI.run(["printf", "ok"], IO::Memory.new, stdout, stderr)

        code.should eq(0)
        JSON.parse(captured[1])["input"].as_s.should eq("printf ok")
      end
    ensure
      server.close
    end
  end

  it "sends search shortcuts and question-like prompts to the default provider" do
    captured = [] of String
    base, server = start_ai_server(captured)
    begin
      with_agent_root(base) do
        stdout = IO::Memory.new
        stderr = IO::Memory.new

        Actra::CLI.run(["search", "forgefed"], IO::Memory.new, stdout, stderr).should eq(0)
        Actra::CLI.run(["?forgefed"], IO::Memory.new, stdout, stderr).should eq(0)
        Actra::CLI.run(["what", "is", "forgefed?"], IO::Memory.new, stdout, stderr).should eq(0)

        JSON.parse(captured[1])["input"].as_s.should eq("search forgefed")
        JSON.parse(captured[3])["input"].as_s.should eq("?forgefed")
        JSON.parse(captured[5])["input"].as_s.should eq("what is forgefed?")
      end
    ensure
      server.close
    end
  end
end
