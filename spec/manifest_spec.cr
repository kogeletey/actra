require "spec"
require "../src/actra/manifest"
require "../src/actra/config"

describe Actra::Manifest do
  it "builds manifest URL candidates with well-known first" do
    urls = Actra::Manifest.manifest_urls("https://example.com/")
    urls[0].should eq("https://example.com/.well-known/actra.json")
    urls[1].should eq("https://example.com/.well-know/actra.json")
  end

  it "parses path aliases and expands tokens" do
    m = Actra::Manifest.parse(%({
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
