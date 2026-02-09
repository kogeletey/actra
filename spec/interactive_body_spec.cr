require "spec"
require "http/server"
require "json"
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

class TtyMemory < IO::Memory
  def tty? : Bool
    true
  end
end

private def start_server(captured : Pointer(String)) : Tuple(String, HTTP::Server)
  openapi = %({
    "openapi":"3.1.0",
    "paths": {
      "/things": {
        "post": { "responses": { "200": { "description":"ok" } } }
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
    when "/things"
      captured.value = ctx.request.body.try(&.gets_to_end) || ""
      ctx.response.content_type = "application/json"
      ctx.response.print %({"ok":true})
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

describe "interactive request body" do
  it "builds JSON from prompts for POST when stdin is a TTY" do
    with_temp_root do |root|
      # Render config for POST /things
      FileUtils.mkdir_p(Wacli::Xdg.config_dir)
      File.write(Wacli::Xdg.config_path, %({
        "render": {
          "pickers": { "prefer_fzf": false },
          "operations": {
            "POST /things": {
              "body": {
                "type": "object",
                "fields": [
                  { "pointer": "/title", "kind": "string", "prompt": "Title", "required": true },
                  { "pointer": "/confidential", "kind": "boolean", "prompt": "Confidential?", "default": false },
                  { "pointer": "/label", "kind": "enum", "prompt": "Label", "values": ["bug", "feature"] }
                ]
              }
            }
          }
        }
      }))

      captured = Pointer(String).malloc(1)
      captured.value = ""
      base, server = start_server(captured)
      begin
        # Title: hello
        # Confidential? default false (blank -> false)
        # Enum choose 2 -> feature
        stdin = TtyMemory.new("hello\n\n2\n")
        stdout = IO::Memory.new
        stderr = IO::Memory.new
        code = Wacli::CLI.run([base, "post", "things"], stdin, stdout, stderr)
        code.should eq(0)

        any = JSON.parse(captured.value)
        any["title"].as_s.should eq("hello")
        any["confidential"].as_bool.should eq(false)
        any["label"].as_s.should eq("feature")
      ensure
        server.close
      end
    end
  end
end

