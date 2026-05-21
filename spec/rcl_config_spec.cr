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

  it "loads configurable @ action menu entries from RCL" do
    cfg = Actra::Config.load_rcl(%(
      at do
        action "notes" do
          label = "Add to Notes"
          kind = "org_todo"
          org_todo_path = "$HOME/org/tasks.org"
          category = "Notes"
        end
      end
    ))

    cfg.at.menu_actions.size.should eq(1)
    action = cfg.at.menu_actions.first
    action.name.should eq("notes")
    action.label.should eq("Add to Notes")
    action.kind.should eq("org_todo")
    action.org_todo_path.should eq(File.join(Actra::Xdg.home, "org", "tasks.org"))
    action.category.should eq("Notes")
  end

  it "loads permissions configuration from RCL" do
    cfg = Actra::Config.load_rcl(%(
      permissions do
        mode = "restrictive"
        sandbox = true
        doom_loop_threshold = 3

        tool "read" do
          allow = ["src/**"]
          ask = ["tmp/**"]
          deny = ["/etc/**"]
        end
      end
    ))

    cfg.permissions.mode.should eq(Actra::PermissionMode::Restrictive)
    cfg.permissions.sandbox.should be_true
    cfg.permissions.doom_loop_threshold.should eq(3)
    cfg.permissions.tools.size.should eq(1)
    cfg.permissions.tools.first.tool.should eq("read")
    cfg.permissions.tools.first.allow.should eq(["src/**"])
    cfg.permissions.tools.first.ask.should eq(["tmp/**"])
    cfg.permissions.tools.first.deny.should eq(["/etc/**"])
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
