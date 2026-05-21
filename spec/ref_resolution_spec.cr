require "spec"
require "http/server"

require "../src/actra/cli"

private def start_server : Tuple(String, HTTP::Server)
  openapi = %({
    "openapi":"3.1.0",
    "components": {
      "schemas": {
        "Thing": {
          "type": "object",
          "required": ["id"],
          "properties": {
            "id": { "type": "string" },
            "count": { "type": "integer" }
          }
        }
      }
    },
    "paths": {
      "/things": {
        "post": {
          "requestBody": {
            "content": {
              "application/json": {
                "schema": { "$ref": "#/components/schemas/Thing" }
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
  base = "http://127.0.0.1:#{addr.port}"
  {base, server}
end

describe "local $ref resolution" do
  it "resolves #/components/schemas refs for help schema and interactive fields" do
    base, server = start_server
    begin
      stdin = IO::Memory.new
      stdout = IO::Memory.new
      stderr = IO::Memory.new
      Actra::CLI.run(["help", base, "post", "things"], stdin, stdout, stderr).should eq(0)

      out = stdout.to_s
      out.should contain("id: string (required)")
      out.should contain("count:")
      out.should contain("/id")
      out.should contain("/count")
    ensure
      server.close
    end
  end
end

