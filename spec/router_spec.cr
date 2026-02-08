require "./spec_helper"

describe Wacli::OpenAPI::Router do
  it "matches a swagger2 operation and extracts path params" do
    doc = Wacli::OpenAPI::Loader.load_file("spec/fixtures/oas2_min.json")
    op = Wacli::OpenAPI::Router.match(doc, "get", ["repos", "alice", "demo", "issues"])
    op.method.should eq("get")
    op.path_template.should eq("/repos/{owner}/{repo}/issues")
    op.path_param_names.should eq(["owner", "repo"])
    op.path_param_values.should eq(["alice", "demo"])
  end

  it "raises on no match" do
    doc = Wacli::OpenAPI::Loader.load_file("spec/fixtures/oas2_min.json")
    expect_raises(Exception) do
      Wacli::OpenAPI::Router.match(doc, "get", ["nope"])
    end
  end
end

