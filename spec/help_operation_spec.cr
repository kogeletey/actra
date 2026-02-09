require "spec"
require "http/server"
require "file_utils"

require "./support/tmpdir"
require "../src/wacli/cli"
require "../src/wacli/xdg"

private def with_temp_root(&)
  SpecTmpdir.with do |root|
    ENV["WACLI_TEST_ROOT"] = root
    begin
      yield root
    ensure
      ENV.delete("WACLI_TEST_ROOT")
    end
  end
end

private def start_server : Tuple(String, HTTP::Server)
  openapi = %({
    "openapi":"3.1.0",
    "paths": {
      "/things": {
        "post": {
          "summary": "Create thing",
          "description": "Creates a thing.\nSecond line.",
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
    when "/.well-known/wacli.json", "/.well-know/wacli.json"
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
  base = "http://127.0.0.1:#{addr.port}"
  {base, server}
end

describe "help (operation detail)" do
  it "prints full description + schema diagram + interactive field preview" do
    with_temp_root do |root|
      base, server = start_server
      begin
        stdin = IO::Memory.new
        stdout = IO::Memory.new
        stderr = IO::Memory.new
        Wacli::CLI.run(["help", base, "post", "things"], stdin, stdout, stderr).should eq(0)

        out = stdout.to_s
        out.should contain("operation: POST /things")
        out.should contain("summary: Create thing")
        out.should contain("description:")
        out.should contain("Creates a thing.")
        out.should contain("Second line.")
        out.should contain("requestBody:")
        out.should contain("schema:")
        out.should contain("title: string (required)")
        out.should contain("label: enum [bug, feature]")
        out.should contain("interactive:")
        out.should contain("/title")
        out.should contain("/label")
      ensure
        server.close
      end
    end
  end
end

