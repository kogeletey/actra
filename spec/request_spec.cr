require "./spec_helper"
require "../src/wacli/request"

describe Wacli::Request do
  it "builds a dry-run with interpolated path and query" do
    req = Wacli::Request.build(
      base_url: "https://example.com/api",
      method: "get",
      path_template: "/repos/{owner}/{repo}/issues",
      path_param_names: ["owner", "repo"],
      path_param_values: ["alice", "demo"],
      query: [{"page", "2"}],
      headers: [{"Accept", "application/json"}],
      json_body: nil,
      bearer_token: nil,
      bearer_header: "Authorization"
    )
    txt = req.to_dry_run
    txt.should contain("GET https://example.com/api/repos/alice/demo/issues?page=2")
    txt.should contain("Accept: application/json")
  end
end

