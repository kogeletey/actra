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

private def with_agent_root(base_url : String, api : String = "openai-responses", &)
  SpecTmpdir.with do |root|
    ENV["ACTRA_TEST_ROOT"] = root
    FileUtils.mkdir_p(Actra::Xdg.config_dir)
    File.write(Actra::Xdg.config_path, %(
      base do
        default_provider = "local"
        default_model = "test-model"
        session_dir = "$HOME/.cache/actra/test-sessions"
      end

      provider "local" do
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
  it "prints help without entering agent/session mode" do
    stdout = IO::Memory.new
    stderr = IO::Memory.new
    code = Actra::CLI.run(["--help"], IO::Memory.new, stdout, stderr)

    code.should eq(1)
    stdout.to_s.should contain("actra agent")
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
        code = Actra::CLI.run(["agent", "--no-session", "--extension", script, "use crystal tool"], IO::Memory.new, stdout, stderr)

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
