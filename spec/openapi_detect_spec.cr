require "./spec_helper"

describe Actra::OpenAPI::Loader do
  it "detects swagger 2.0" do
    doc = Actra::OpenAPI::Loader.load_file("spec/fixtures/oas2_min.json")
    doc.version.should eq(Actra::OpenAPI::Version::Swagger2)
  end

  it "detects openapi 3.0" do
    doc = Actra::OpenAPI::Loader.load_file("spec/fixtures/oas3_min.json")
    doc.version.should eq(Actra::OpenAPI::Version::OpenAPI30)
  end

  it "detects openapi 3.1" do
    doc = Actra::OpenAPI::Loader.load_file("spec/fixtures/oas31_min.json")
    doc.version.should eq(Actra::OpenAPI::Version::OpenAPI31)
  end
end

