require "spec"
require "json"
require "file_utils"

require "./support/tmpdir"
require "../src/actra/tool_resolver"
require "../src/actra/tool_key"
require "../src/actra/xdg"
require "../src/actra/config"

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

describe "ain precedence" do
  it "uses cached ain spec before attempting network manifest/fallback" do
    with_temp_root do |root|
      tool_ref = "https://example.org"
      key = Actra::ToolKey.for(tool_ref)

      # Create cached spec file
      cached = File.join(root, "cache", "actra", "ains", "#{key}.json")
      FileUtils.mkdir_p(File.dirname(cached))
      File.write(cached, File.read("spec/fixtures/oas3_min.json"))

      # Write lock pointing to cached spec
      lock_dir = File.join(root, "config", "actra")
      FileUtils.mkdir_p(lock_dir)
      lock_path = File.join(lock_dir, "actra.lock")
      File.write(lock_path, %({
        "fileVersion": 1,
        "ains": {
          "#{key}": {
            "integrity": "x",
            "source": "https://example.org/openapi.json",
            "installPath": "#{cached}",
            "openapiVersion": "3.0"
          }
        }
      }))

      cfg = Actra::Config.new("/tmp/wa.db", "/tmp", {"registry" => "https://actra.ofs.lol"}, Actra::Render::Config.default)
      resolved = Actra::ToolResolver.resolve(tool_ref, cfg)
      resolved.source.should eq("ain")
      resolved.api_url.should eq(cached)
    end
  end
end
