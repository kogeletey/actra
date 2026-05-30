require "./spec_helper"

describe Actra::OpenAPI::BaseUrl do
  it "computes swagger2 base url from schemes+host+basePath" do
    doc = Actra::OpenAPI::Loader.load_file("spec/fixtures/oas2_min.json")
    Actra::OpenAPI::BaseUrl.compute(doc, "example.com").should eq("https://example.com/api")
  end

  it "uses servers[0].url for openapi 3.x" do
    doc = Actra::OpenAPI::Loader.load_file("spec/fixtures/oas3_min.json")
    Actra::OpenAPI::BaseUrl.compute(doc, "example.com").should eq("https://api.example.com/v1")
  end

  it "falls back to tool_ref base when servers missing (openapi 3.1)" do
    doc = Actra::OpenAPI::Loader.load_file("spec/fixtures/oas31_min.json")
    Actra::OpenAPI::BaseUrl.compute(doc, "https://example.com").should eq("https://example.com")
  end
end

