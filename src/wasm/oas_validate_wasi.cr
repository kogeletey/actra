require "json"

require "../wacli/openapi/document"
require "../wacli/openapi/compat"
require "../wacli/openapi/detector"

# Minimal WASI CLI: validate OpenAPI JSON from stdin and print a text report.
# This file intentionally avoids any HTTP/DB usage so it can target wasm32-wasi.

json_text = STDIN.gets_to_end
if json_text.strip.empty?
  STDERR.puts "expected OpenAPI JSON on stdin"
  exit 64
end

begin
  any = JSON.parse(json_text)
rescue ex
  STDERR.puts "invalid JSON: #{ex.message}"
  exit 3
end

doc =
  begin
    Wacli::OpenAPI::Detector.detect(any)
  rescue ex
    STDERR.puts ex.message
    exit 2
  end

report = Wacli::OpenAPI::Compat.validate(doc)
puts report.to_text
exit report.exit_code
