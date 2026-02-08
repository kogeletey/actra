require "./spec_helper"

describe Wacli::ToolKey do
  it "normalizes host across scheme variations" do
    Wacli::ToolKey.for("example.org").should eq("example.org")
    Wacli::ToolKey.for("https://example.org").should eq("example.org")
    Wacli::ToolKey.for("http://example.org:8080").should eq("example.org:8080")
  end

  it "keeps registry refs as-is" do
    Wacli::ToolKey.for("registry:forgejo").should eq("registry:forgejo")
  end
end

