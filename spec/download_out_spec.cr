require "spec"
require "http/server"
require "file_utils"

require "./support/tmpdir"
require "../src/actra/cli"

private def with_temp_root(&)
  SpecTmpdir.with do |root|
    ENV["ACTRA_TEST_ROOT"] = root
    begin
      yield root
    ensure
      ENV.delete("ACTRA_TEST_ROOT")
    end
  end
end

private def start_server : Tuple(String, HTTP::Server)
  openapi = %({
    "openapi":"3.1.0",
    "paths": {
      "/file": { "get": { "responses": { "200": { "description":"ok" } } } }
    }
  })

  server = HTTP::Server.new do |ctx|
    case ctx.request.path
    when "/.well-known/actra.json", "/.well-know/actra.json"
      ctx.response.status_code = 404
    when "/openapi.json"
      ctx.response.content_type = "application/json"
      ctx.response.print openapi
    when "/file"
      ctx.response.status_code = 200
      ctx.response.headers["Content-Disposition"] = "attachment; filename=\"x.txt\""
      ctx.response.content_type = "application/octet-stream"
      ctx.response.print "hello"
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

describe "download to --out" do
  it "saves response bytes to a file" do
    with_temp_root do |root|
      base, server = start_server
      begin
        out_path = File.join(root, "x.txt")
        stdin = IO::Memory.new
        stdout = IO::Memory.new
        stderr = IO::Memory.new
        code = Actra::CLI.run([base, "get", "file", "--out", out_path], stdin, stdout, stderr)
        code.should eq(0)
        File.read(out_path).should eq("hello")
        stderr.to_s.should contain("saved:")
      ensure
        server.close
      end
    end
  end
end

