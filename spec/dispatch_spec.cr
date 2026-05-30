require "spec"
require "file_utils"

require "./support/tmpdir"
require "../src/actra/cli"
require "../src/actra/xdg"

private def with_temp_root(&)
  SpecTmpdir.with do |root|
    ENV["ACTRA_TEST_ROOT"] = root
    begin
      yield root
    ensure
      ENV.delete("ACTRA_TEST_ROOT")
    end
  end
end

describe "dispatch" do
  it "resolves configured actor commands into ForgeFed Create Ticket dry-runs" do
    with_temp_root do
      FileUtils.mkdir_p(Actra::Xdg.config_dir)
      File.write(Actra::Xdg.config_path, %(
        base do
          default_server = "lefine.pro"
        end

        server "lefine.pro" do
          base_url = "https://lefine.pro"
          actor_id = "https://lefine.pro/actor/shell"
          inbox = "/inbox"
          outbox = "/outbox"

          actor "code" do
            command = "@code"
            inbox = "/inbox/code"
            outbox = "/outbox/code"
            work_type = "code"
          end
        end
      ))

      stdout = IO::Memory.new
      stderr = IO::Memory.new
      code = Actra::CLI.run(["dispatch", "--command", "@code", "--dry-run", "--", "fix parser"], IO::Memory.new, stdout, stderr)

      code.should eq(0)
      stdout.to_s.should contain("POST https://lefine.pro/inbox/code")
      stdout.to_s.should contain(%("type":"Create"))
      stdout.to_s.should contain(%("type":"Ticket"))
      stdout.to_s.should contain(%("workType":"code"))
    end
  end

  it "routes @actor@domain handles into a fediverse actor inbox dry-run" do
    with_temp_root do
      stdout = IO::Memory.new
      stderr = IO::Memory.new
      code = Actra::CLI.run(["dispatch", "--command", "@alice@mastodon.social", "--dry-run", "--", "create task"], IO::Memory.new, stdout, stderr)

      code.should eq(0)
      stdout.to_s.should contain("POST https://mastodon.social/users/alice/inbox")
      stdout.to_s.should contain(%("summary":"@alice@mastodon.social"))
      stdout.to_s.should contain(%("type":"Ticket"))
    end
  end

  it "routes @claude and @codex to local CLIs" do
    with_temp_root do
      stdout = IO::Memory.new
      stderr = IO::Memory.new

      Actra::CLI.run(["dispatch", "--command", "@claude", "--dry-run", "--", "use claude sdk"], IO::Memory.new, stdout, stderr).should eq(0)
      Actra::CLI.run(["dispatch", "--command", "@codex", "--dry-run", "--", "use codex api"], IO::Memory.new, stdout, stderr).should eq(0)

      out = stdout.to_s
      out.should contain("LOCAL claude")
      out.should contain("'claude' '-p' 'use claude sdk'")
      out.should contain("LOCAL codex")
      out.should contain("'codex' 'exec' 'use codex api'")
    end
  end

  it "uses LEFINE_TOKEN for Lefine actor dry-runs without leaking the token" do
    with_temp_root do
      ENV["LEFINE_TOKEN"] = "secret-token"
      begin
        stdout = IO::Memory.new
        stderr = IO::Memory.new
        code = Actra::CLI.run(["dispatch", "--command", "@code", "--dry-run", "--", "use lefine"], IO::Memory.new, stdout, stderr)

        code.should eq(0)
        stdout.to_s.should contain("Authorization: Bearer <redacted>")
        stdout.to_s.should_not contain("secret-token")
      ensure
        ENV.delete("LEFINE_TOKEN")
      end
    end
  end
end
