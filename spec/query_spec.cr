require "spec"
require "http/server"

require "../src/actra/cli"

private def start_query_server : Tuple(String, HTTP::Server)
  openapi = %({
    "openapi":"3.1.0",
    "paths": {
      "/ping": { "get": { "summary": "Ping", "responses": { "200": { "description":"ok" } } } },
      "/things": {
        "post": {
          "summary": "Create thing",
          "requestBody": {
            "required": true,
            "content": {
              "application/json": {
                "schema": {
                  "type": "object",
                  "required": ["title"],
                  "properties": {
                    "title": { "type": "string" },
                    "label": { "type": "string", "enum": ["bug", "feature"] }
                  }
                }
              }
            }
          },
          "responses": { "200": { "description":"ok" } }
        }
      }
    }
  })

  server = HTTP::Server.new do |ctx|
    case ctx.request.path
    when "/.well-known/actra.json", "/.well-know/actra.json"
      ctx.response.status_code = 404
    when "/openapi.json"
      ctx.response.content_type = "application/json"
      ctx.response.print openapi
    else
      ctx.response.status_code = 404
      ctx.response.print "not found"
    end
  end

  addr = server.bind_tcp("127.0.0.1", 0)
  spawn { server.listen }
  {"http://127.0.0.1:#{addr.port}", server}
end

describe "query shortcut" do
  it "prints @ shortcut help" do
    stdout = IO::Memory.new
    stderr = IO::Memory.new
    code = Actra::CLI.run(["@?"], IO::Memory.new, stdout, stderr)

    code.should eq(0)
    stdout.to_s.should contain("@file")
    stdout.to_s.should contain("@ <command...>")
    stdout.to_s.should contain("@actor@domain")
    stdout.to_s.should_not contain("/@")
  end

  it "prints actor and @file completions" do
    stdout = IO::Memory.new
    stderr = IO::Memory.new
    code = Actra::CLI.run(["complete", "at", "@"], IO::Memory.new, stdout, stderr)

    code.should eq(0)
    out = stdout.to_s
    out.should contain("@?")
    out.should contain("@")
    out.should contain("@file")
    out.should contain("@code")
    out.should contain("@plan")
    out.should contain("@claude")
    out.should contain("@codex")
    out.should_not contain("/@")
  end

  it "prints tool info by default" do
    base, server = start_query_server
    begin
      stdout = IO::Memory.new
      stderr = IO::Memory.new
      code = Actra::CLI.run(["?#{base}"], IO::Memory.new, stdout, stderr)

      code.should eq(0)
      stdout.to_s.should contain("tool: #{base}")
      stdout.to_s.should contain("operations:")
      stdout.to_s.should contain("GET /ping - Ping")
    ensure
      server.close
    end
  end

  it "supports ? as a standalone command" do
    base, server = start_query_server
    begin
      stdout = IO::Memory.new
      stderr = IO::Memory.new
      code = Actra::CLI.run(["?", base], IO::Memory.new, stdout, stderr)

      code.should eq(0)
      stdout.to_s.should contain("tool: #{base}")
      stdout.to_s.should contain("GET /ping - Ping")
    ensure
      server.close
    end
  end

  it "generates Markdown docs" do
    base, server = start_query_server
    begin
      stdout = IO::Memory.new
      stderr = IO::Memory.new
      code = Actra::CLI.run(["?#{base}", "docs", "post", "things"], IO::Memory.new, stdout, stderr)

      code.should eq(0)
      stdout.to_s.should contain("# #{base}")
      stdout.to_s.should contain("## `POST /things`")
      stdout.to_s.should contain("### Interactive Fields")
      stdout.to_s.should contain("`/title`")
    ensure
      server.close
    end
  end
end
