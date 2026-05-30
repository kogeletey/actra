require "spec"

require "./support/tmpdir"
require "../src/actra/session"

describe Actra::AgentSession do
  it "tracks pending permission requests with allow and revoke events" do
    SpecTmpdir.with do |root|
      session = Actra::AgentSession.open(root, "permissions")
      request = Actra::PermissionRequest.new("read", "src/actra/cli.cr", "src/actra/cli.cr")

      session.append_permission_request(request)
      session.append_permission_request(request)
      session.pending_permission_requests.size.should eq(1)
      session.pending_permission_requests.first.reason.should be_nil

      session.append_permission_allow("read", "src/**")
      session.pending_permission_requests.empty?.should be_true

      session.append_permission_revoke("read", "src/**")
      session.pending_permission_requests.size.should eq(1)

      session.append_permission_deny("read", "src/**")
      session.pending_permission_requests.empty?.should be_true
      session.permission_denials.first.pattern.should eq("src/**")
      session.permission_allowlist.empty?.should be_true

      session.append_permission_allow("read", "src/**")
      session.permission_denials.empty?.should be_true
      session.permission_allowlist.first.pattern.should eq("src/**")
      session.permission_decisions.first[0].should eq("allow")
      session.pending_permission_requests.empty?.should be_true

      session.append_permission_clear
      session.permission_decisions.empty?.should be_true
      session.pending_permission_requests.size.should eq(1)
    end
  end
end
