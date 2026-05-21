require "./spec_helper"

describe Actra::ToolKey do
  it "normalizes host across scheme variations" do
    Actra::ToolKey.for("example.org").should eq("example.org")
    Actra::ToolKey.for("https://example.org").should eq("example.org")
    Actra::ToolKey.for("http://example.org:8080").should eq("example.org:8080")
  end

  it "keeps registry refs as-is" do
    Actra::ToolKey.for("registry:forgejo").should eq("registry:forgejo")
  end
end

