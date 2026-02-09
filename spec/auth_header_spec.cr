require "spec"
require "http/server"

require "./support/tmpdir"
require "../src/wacli/cli"

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

private def start_fallback_server(openapi_body : String) : Tuple(String, HTTP::Server)
  server = HTTP::Server.new do |ctx|
    case ctx.request.path
    when "/.well-known/wacli.json", "/.well-know/wacli.json"
      ctx.response.status_code = 404
      ctx.response.print "nope"
    when "/openapi.json"
      ctx.response.content_type = "application/json"
      ctx.response.print openapi_body
    when "/ping"
      ctx.response.content_type = "text/plain"
      ctx.response.print "pong"
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

describe "auth header injection" do
  it "injects Authorization header in fallback mode" do
    with_temp_root do
      openapi = %({
        "openapi":"3.1.0",
        "paths": { "/ping": { "get": { "responses": { "200": { "description":"ok" } } } } }
      })

      base, server = start_fallback_server(openapi)
      begin
        stdin_io = IO::Memory.new
        stdout_io = IO::Memory.new
        stderr_io = IO::Memory.new
        Wacli::CLI.run(["auth", base, "--bearer", "ABC"], stdin_io, stdout_io, stderr_io).should eq(0)

        stdin_io2 = IO::Memory.new
        stdout_io2 = IO::Memory.new
        stderr_io2 = IO::Memory.new
        Wacli::CLI.run([base, "get", "ping", "--dry-run"], stdin_io2, stdout_io2, stderr_io2).should eq(0)
        stdout_io2.to_s.should contain("Authorization: Bearer ABC")
      ensure
        server.close
      end
    end
  end
end
