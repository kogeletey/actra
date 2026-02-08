require "spec"
require "http/server"
require "socket"

require "../src/wacli/tool_resolver"
require "../src/wacli/config"

private def start_server(openapi_body : String) : Tuple(String, HTTP::Server)
  server = HTTP::Server.new do |ctx|
    case ctx.request.path
    when "/.well-known/wacli.json", "/.well-know/wacli.json"
      ctx.response.status_code = 404
      ctx.response.print "nope"
    when "/openapi.json"
      ctx.response.content_type = "application/json"
      ctx.response.print openapi_body
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

describe Wacli::ToolResolver do
  it "falls back to /openapi.json when manifest is missing" do
    openapi = File.read("spec/fixtures/oas3_min.json")
    base, server = start_server(openapi)
    begin
      cfg = Wacli::Config.new("/tmp/wa.db", "/tmp", {"registry" => base})
      resolved = Wacli::ToolResolver.resolve(base, cfg)
      resolved.source.should eq("fallback")
      resolved.api_url.should eq("#{base}/openapi.json")
    ensure
      server.close
    end
  end
end

