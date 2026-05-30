require "./spec_helper"

describe Actra::OpenAPI::Compat do
  it "accepts minimal swagger 2.0 with paths" do
    doc = Actra::OpenAPI::Loader.load_file("spec/fixtures/oas2_min.json")
    report = Actra::OpenAPI::Compat.validate(doc)
    report.ok.should be_true
    report.exit_code.should eq(0)
  end

  it "rejects missing paths" do
    doc = Actra::OpenAPI::Loader.load_json(%({"openapi":"3.1.0"}))
    report = Actra::OpenAPI::Compat.validate(doc)
    report.ok.should be_false
    report.errors.join("\n").should contain("paths")
  end
end

