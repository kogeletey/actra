require "spec"
require "file_utils"

require "./support/tmpdir"
require "../src/actra/config"

describe Actra::Config do
  it "does not model claude and codex as default Lefine actors" do
    server = Actra::Config.default.server("lefine.pro").not_nil!

    server.actor_for_command("@claude").should be_nil
    server.actor_for_command("@codex").should be_nil
  end

  it "loads base and server actor blocks from RCL without a root wrapper" do
    cfg = Actra::Config.load_rcl(%(
      base do
        default_server = "lefine.pro"
        db_path = "$HOME/.cache/actra/test.db"
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

    cfg.default_server.should eq("lefine.pro")
    server = cfg.server("lefine.pro").not_nil!
    server.base_url.should eq("https://lefine.pro")
    server.actor_for_command("@code").not_nil!.work_type.should eq("code")
  end

  it "loads vifm-style filetype editor associations from RCL" do
    cfg = Actra::Config.load_rcl(%(
      filetype "crystal" do
        extensions = [".cr"]
        editor = "nvim"
      end

      filetype "images" do
        patterns = ["*.png", "*.jpg"]
        editor = "xdg-open"
      end
    ))

    cfg.editor_for_file("/tmp/app/main.cr").should eq("nvim")
    cfg.editor_for_file("/tmp/screenshot.png").should eq("xdg-open")
    cfg.editor_for_file("/tmp/readme.md").should be_nil
  end

  it "loads config.rcl from .config/astra before the legacy actra path" do
    SpecTmpdir.with do |root|
      ENV["ACTRA_TEST_ROOT"] = root
      begin
        FileUtils.mkdir_p(Actra::Xdg.config_dir)
        FileUtils.mkdir_p(Actra::Xdg.astra_config_dir)
        File.write(Actra::Xdg.config_path, %(base do\n  default_server = "legacy.example"\nend\n))
        File.write(Actra::Xdg.astra_config_path, %(base do\n  default_server = "astra.example"\nend\n))

        Actra::Config.load.default_server.should eq("astra.example")
      ensure
        ENV.delete("ACTRA_TEST_ROOT")
      end
    end
  end
end
