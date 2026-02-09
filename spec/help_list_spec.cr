require "spec"
require "http/server"

require "../src/wacli/cli"

private def start_server : Tuple(String, HTTP::Server)
  openapi = %({
    "openapi":"3.1.0",
    "paths": {
      "/ping": { "get": { "summary": "Ping", "responses": { "200": { "description":"ok" } } } },
      "/things": {
        "get": { "summary": "List things", "responses": { "200": { "description":"ok" } } },
        "post": { "description": "Create a thing", "responses": { "200": { "description":"ok" } } }
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

describe "help (operation list)" do
  it "prints operation summaries/descriptions" do
    base, server = start_server
    begin
      stdin = IO::Memory.new
      stdout = IO::Memory.new
      stderr = IO::Memory.new
      Wacli::CLI.run(["help", base], stdin, stdout, stderr).should eq(0)

      out = stdout.to_s
      out.should contain("operations:")
      out.should contain("GET /ping - Ping")
      out.should contain("GET /things - List things")
      out.should contain("POST /things - Create a thing")
    ensure
      server.close
    end
  end
end

