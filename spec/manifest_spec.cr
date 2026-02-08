require "spec"
require "../src/wacli/manifest"
require "../src/wacli/config"

describe Wacli::Manifest do
  it "builds manifest URL candidates with well-known first" do
    urls = Wacli::Manifest.manifest_urls("https://example.com/")
    urls[0].should eq("https://example.com/.well-known/wacli.json")
    urls[1].should eq("https://example.com/.well-know/wacli.json")
  end

  it "parses path aliases and expands tokens" do
    m = Wacli::Manifest.parse(%({
      "api":"https://example.com/openapi.json",
      "settings":{
        "aliases":[{"alias":["i","issues"],"type":"path","content":"/repos/{owner}/{repo}/issues"}]
      }
    }))
    m.path_aliases["i"].should eq("/repos/{owner}/{repo}/issues")
    m.path_aliases["issues"].should eq("/repos/{owner}/{repo}/issues")
    m.expand_path_tokens(["issues", "alice", "demo"]).should eq(["repos", "alice", "demo", "issues"])
  end
end
