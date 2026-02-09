require "option_parser"
require "json"

require "../wacli/openapi/document"
require "../wacli/openapi/compat"
require "../wacli/openapi/detector"

require "./config"
require "./json_db"

# WASI CLI: validate OpenAPI JSON from stdin and store/lookup reports in a JSON db.
#
# Config file (JSON):
#   { "dbPath": "data/wacli-db.json" }
#
# Commands:
#   validate --config cfg.json --key example.org < openapi.json
#   show --config cfg.json --key example.org
cmd = "validate"
config_path = ""
key = "default"

OptionParser.parse do |p|
  p.banner = "usage: wacli-wasm-db <validate|show> --config FILE [--key KEY]"
  p.on("--config FILE", "config JSON with dbPath") { |v| config_path = v }
  p.on("--key KEY", "db key (default: #{key})") { |v| key = v }
  p.on("-h", "--help", "show help") { puts p; exit 0 }
  p.unknown_args do |args|
    cmd = args[0]? || cmd
  end
end

if config_path.empty?
  STDERR.puts "missing --config"
  exit 64
end

cfg =
  begin
    Wacli::Wasm::Config.load(config_path)
  rescue ex
    STDERR.puts "config error: #{ex.message}"
    exit 64
  end

db_path = cfg.db_path
db = Wacli::Wasm::JsonDb.load(db_path)

case cmd
when "show"
  rep = db.get_report(key)
  unless rep
    STDERR.puts "no report for key: #{key}"
    exit 1
  end
  puts rep.report
  exit 0
when "validate"
  json_text = STDIN.gets_to_end
  if json_text.strip.empty?
    STDERR.puts "expected OpenAPI JSON on stdin"
    exit 64
  end

  any =
    begin
      JSON.parse(json_text)
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
  text = report.to_text
  puts text

  db.set_report(key, doc.version_string, text)
  db.save(db_path)
  exit report.exit_code
else
  STDERR.puts "unknown command: #{cmd} (expected validate|show)"
  exit 64
end
