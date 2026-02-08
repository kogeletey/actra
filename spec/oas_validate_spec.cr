require "./spec_helper"

describe Wacli::OpenAPI::Compat do
  it "accepts minimal swagger 2.0 with paths" do
    doc = Wacli::OpenAPI::Loader.load_file("spec/fixtures/oas2_min.json")
    report = Wacli::OpenAPI::Compat.validate(doc)
    report.ok.should be_true
    report.exit_code.should eq(0)
  end

  it "rejects missing paths" do
    doc = Wacli::OpenAPI::Loader.load_json(%({"openapi":"3.1.0"}))
    report = Wacli::OpenAPI::Compat.validate(doc)
    report.ok.should be_false
    report.errors.join("\n").should contain("paths")
  end
end

