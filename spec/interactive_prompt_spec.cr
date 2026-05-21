require "spec"
require "file_utils"

require "./support/tmpdir"
require "../src/actra/cli"
require "../src/actra/interactive/prompt"

private def with_fake_fzf(action : String? = nil, executable : Bool = false, selection : String = "file    src/demo.cr", &)
  SpecTmpdir.with do |root|
    bin = File.join(root, "bin")
    FileUtils.mkdir_p(bin)
    FileUtils.mkdir_p(File.join(root, "src"))
    demo = File.join(root, "src", "demo.cr")
    if executable
      File.write(demo, "#!/bin/sh\nprintf 'ran demo\\n'\n")
      File.chmod(demo, 0o755)
    else
      File.write(demo, "")
    end

    old_path = ENV["PATH"]?
    old_root = ENV["ACTRA_TEST_ROOT"]?
    ENV["PATH"] = "#{bin}:#{old_path}"
    ENV["ACTRA_TEST_ROOT"] = root
    if action
      ENV["ACTRA_TEST_FZF_ACTION"] = action
    else
      ENV.delete("ACTRA_TEST_FZF_ACTION")
    end
    ENV["ACTRA_TEST_FZF_SELECTION"] = selection
    begin
      Dir.cd(root) { yield root, bin }
    ensure
      if old_path
        ENV["PATH"] = old_path
      else
        ENV.delete("PATH")
      end
      if old_root
        ENV["ACTRA_TEST_ROOT"] = old_root
      else
        ENV.delete("ACTRA_TEST_ROOT")
      end
      ENV.delete("ACTRA_TEST_FZF_ACTION")
      ENV.delete("ACTRA_TEST_FZF_SELECTION")
    end
  end
end

describe Actra::Interactive::PickerTui do
  it "formats selected files as shell-safe context tokens" do
    tokens = Actra::Interactive::PickerTui.context_tokens(["./src/actra/cli.cr", "docs/file name.md"])

    tokens.should eq("'@src/actra/cli.cr' '@docs/file name.md'")
  end

  it "lists file context candidates for shell completion" do
    SpecTmpdir.with do |root|
      FileUtils.mkdir_p(File.join(root, "src"))
      File.write(File.join(root, "src", "demo.cr"), "")

      Dir.cd(root) do
        candidates = Actra::Interactive::PickerTui.file_context_candidates("@src")
        candidates.should contain("@src/demo.cr")
      end
    end
  end

  it "opens the file submenu before attaching a selected non-executable file" do
    with_fake_fzf("insert @path in console") do
      stdout = IO::Memory.new
      stderr = IO::Memory.new

      code = Actra::CLI.run(["@", "@src/demo.cr"], IO::Memory.new, stdout, stderr)

      code.should eq(0)
      stdout.to_s.should eq("'@src/demo.cr'\n")
    end
  end

  it "starts @ file search with the provided query" do
    with_fake_fzf("insert @path in console") do |root, _bin|
      stdout = IO::Memory.new
      stderr = IO::Memory.new

      code = Actra::CLI.run(["@", "demo"], IO::Memory.new, stdout, stderr)

      code.should eq(0)
      stdout.to_s.should contain("file    src/demo.cr")
    end
  end

  it "prints action-specific @ previews" do
    with_fake_fzf do
      stdout = IO::Memory.new
      stderr = IO::Memory.new

      Actra::CLI.run(["@", "--mode-preview", "file", "demo"], IO::Memory.new, stdout, stderr).should eq(0)
      stdout.to_s.should contain("file    src/demo.cr")
      stdout.to_s.should_not contain("actor   @code")

      stdout = IO::Memory.new
      stderr = IO::Memory.new
      Actra::CLI.run(["@", "--action-preview", "code", "demo"], IO::Memory.new, stdout, stderr).should eq(0)
      stdout.to_s.should contain("action  code: '@code' 'demo'")
      stdout = IO::Memory.new
      stderr = IO::Memory.new
      Actra::CLI.run(["@", "--action-preview", "agent", "what do"], IO::Memory.new, stdout, stderr).should eq(0)
      stdout.to_s.should contain("action  agent: actra agent")

      stdout = IO::Memory.new
      stderr = IO::Memory.new
      Actra::CLI.run(["@", "--action-preview", "statistics", "local"], IO::Memory.new, stdout, stderr).should eq(0)
      stdout.to_s.should contain("action  stats: show actra @ --action stats 'local'")

      stdout = IO::Memory.new
      stderr = IO::Memory.new
      Actra::CLI.run(["@", "--action-preview", "bogus", "demo"], IO::Memory.new, stdout, stderr).should eq(1)
      stdout.to_s.should eq("")
      stderr.to_s.should contain("unknown @ action: bogus")
    end
  end

  it "prints action previews without executing" do
    stdout = IO::Memory.new
    stderr = IO::Memory.new

    code = Actra::CLI.run(["@", "--action-preview", "assistant", "printf", "ok"], IO::Memory.new, stdout, stderr)

    code.should eq(0)
    stdout.to_s.should contain("action  assistant: 'printf' 'ok'")

    stdout = IO::Memory.new
    stderr = IO::Memory.new
    code = Actra::CLI.run(["@", "--action-preview", "agent", "analyze", "logs"], IO::Memory.new, stdout, stderr)
    code.should eq(0)
    stdout.to_s.should contain("action  agent: actra agent")

    stdout = IO::Memory.new
    code = Actra::CLI.run(["@", "--action-preview", "background", "printf", "ok"], IO::Memory.new, stdout, stderr)

    code.should eq(0)
    stdout.to_s.should contain("action  background: 'printf' 'ok'")

    stdout = IO::Memory.new
    stderr = IO::Memory.new
    code = Actra::CLI.run(["@", "--action", "agent"], IO::Memory.new, stdout, stderr)
    code.should eq(1)
    stderr.to_s.should contain("missing text for action")

    with_fake_fzf do
      stdout = IO::Memory.new
      stderr = IO::Memory.new

      code = Actra::CLI.run(["@", "--action", "stats"], IO::Memory.new, stdout, stderr)

      code.should eq(0)
      stdout.to_s.should contain("sessions:")
      stdout.to_s.should contain("messages:")

      stdout = IO::Memory.new
      stderr = IO::Memory.new
      code = Actra::CLI.run(["@", "--action", "statistics"], IO::Memory.new, stdout, stderr)
      code.should eq(0)
      stdout.to_s.should contain("sessions:")
      stdout.to_s.should contain("messages:")
    end
  end

  it "runs an executable file from the file submenu" do
    with_fake_fzf("run executable", true) do
      stdout = IO::Memory.new
      stderr = IO::Memory.new

      code = Actra::CLI.run(["@", "@src/demo.cr"], IO::Memory.new, stdout, stderr)

      code.should eq(0)
      stdout.to_s.should eq("ran demo\n")
    end
  end

  it "prints a file attachment from the file submenu" do
    with_fake_fzf("insert @path in console") do
      stdout = IO::Memory.new
      stderr = IO::Memory.new

      code = Actra::CLI.run(["@", "@src/demo.cr"], IO::Memory.new, stdout, stderr)

      code.should eq(0)
      stdout.to_s.should eq("'@src/demo.cr'\n")
    end
  end

  it "copies an absolute path from the file action menu" do
    with_fake_fzf("copy absolute path") do |root, bin|
      copy_out = File.join(root, "copied.txt")
      wl_copy = File.join(bin, "wl-copy")
      File.write(wl_copy, <<-SH)
        #!/bin/sh
        cat > #{copy_out}
        SH
      File.chmod(wl_copy, 0o755)

      stdout = IO::Memory.new
      stderr = IO::Memory.new
      code = Actra::CLI.run(["@", "@src/demo.cr"], IO::Memory.new, stdout, stderr)
      absolute = File.join(root, "src", "demo.cr")

      code.should eq(0)
      File.read(copy_out).should eq(absolute)
      stdout.to_s.should eq("#{absolute}\n")
      stderr.to_s.should contain("copied absolute path")
    end
  end

  it "copies from the file action menu" do
    with_fake_fzf("copy absolute path") do |root, bin|
      copy_out = File.join(root, "copied.txt")
      wl_copy = File.join(bin, "wl-copy")
      File.write(wl_copy, <<-SH)
        #!/bin/sh
        cat > #{copy_out}
        SH
      File.chmod(wl_copy, 0o755)

      stdout = IO::Memory.new
      stderr = IO::Memory.new
      code = Actra::CLI.run(["@", "@src/demo.cr"], IO::Memory.new, stdout, stderr)
      absolute = File.join(root, "src", "demo.cr")

      code.should eq(0)
      File.read(copy_out).should eq(absolute)
    end
  end

  it "inserts an absolute path through the shell hook marker" do
    with_fake_fzf("insert absolute path in console") do |root, _bin|
      old_hook = ENV["ACTRA_SHELL_HOOK"]?
      ENV["ACTRA_SHELL_HOOK"] = "1"
      begin
        stdout = IO::Memory.new
        stderr = IO::Memory.new
        code = Actra::CLI.run(["@", "@src/demo.cr"], IO::Memory.new, stdout, stderr)
        absolute = File.join(root, "src", "demo.cr")

        code.should eq(0)
        stdout.to_s.should eq("__ACTRA_INSERT__'#{absolute}'\n")
      ensure
        if old_hook
          ENV["ACTRA_SHELL_HOOK"] = old_hook
        else
          ENV.delete("ACTRA_SHELL_HOOK")
        end
      end
    end
  end

  it "emits a cd marker for the file folder through the shell hook" do
    with_fake_fzf("go to folder") do |root, _bin|
      old_hook = ENV["ACTRA_SHELL_HOOK"]?
      ENV["ACTRA_SHELL_HOOK"] = "1"
      begin
        stdout = IO::Memory.new
        stderr = IO::Memory.new
        code = Actra::CLI.run(["@", "@src/demo.cr"], IO::Memory.new, stdout, stderr)

        code.should eq(0)
        stdout.to_s.should eq("__ACTRA_CD__#{File.join(root, "src")}\n")
      ensure
        if old_hook
          ENV["ACTRA_SHELL_HOOK"] = old_hook
        else
          ENV.delete("ACTRA_SHELL_HOOK")
        end
      end
    end
  end

  it "runs an executable from the file action menu" do
    with_fake_fzf("run executable", true) do
      stdout = IO::Memory.new
      stderr = IO::Memory.new

      code = Actra::CLI.run(["@", "@src/demo.cr"], IO::Memory.new, stdout, stderr)

      code.should eq(0)
      stdout.to_s.should eq("ran demo\n")
    end
  end

  it "uses @ as an actors, actions, and file attachment search entrypoint" do
    with_fake_fzf do |_root, _bin|
      stdout = IO::Memory.new
      stderr = IO::Memory.new

      code = Actra::CLI.run(["@"], IO::Memory.new, stdout, stderr)

      code.should eq(0)
      stdout.to_s.should contain("actor   @code")
      stdout.to_s.should_not contain("action  ")
      stdout.to_s.should contain("file    src/demo.cr")
    end
  end

  it "prints a selected actor when no task text is provided" do
    with_fake_fzf do |root, _bin|
      FileUtils.mkdir_p(Actra::Xdg.astra_config_dir)
      File.write(Actra::Xdg.astra_config_path, %(
        server "local" do
          base_url = "https://example.test"
          actor_id = "https://example.test/actor/shell"
          inbox = "/inbox"
          outbox = "/outbox"

          actor "review" do
            command = "@review"
            inbox = "/inbox/review"
            outbox = "/outbox/review"
            work_type = "review"
          end
        end
      ))

      stdout = IO::Memory.new
      stderr = IO::Memory.new

      code = Actra::CLI.run(["@", "@review"], IO::Memory.new, stdout, stderr)

      code.should eq(0)
      stdout.to_s.should eq("@review\n")
    end
  end

  it "dispatches task text to a selected actor" do
    with_fake_fzf do |_root, bin|
      codex = File.join(bin, "codex")
      File.write(codex, <<-SH)
        #!/bin/sh
        printf '%s\\n' "$@"
        SH
      File.chmod(codex, 0o755)

      stdout = IO::Memory.new
      stderr = IO::Memory.new
      code = Actra::CLI.run(["@", "@codex", "fix", "parser"], IO::Memory.new, stdout, stderr)

      code.should eq(0)
      stdout.to_s.should eq("exec\nfix parser\n")
    end
  end

  it "runs a configured action selected from the @ launcher" do
    with_fake_fzf do |root, _bin|
      todo_path = File.join(root, "notes", "tasks.org")
      FileUtils.mkdir_p(Actra::Xdg.astra_config_dir)
      File.write(Actra::Xdg.astra_config_path, %(
        at do
          action "notes" do
            label = "Add to Notes"
            kind = "org_todo"
            org_todo_path = "#{todo_path}"
            category = "Notes"
          end
        end
      ))

      stdout = IO::Memory.new
      stderr = IO::Memory.new
      code = Actra::CLI.run(["@", "Add to Notes", "write", "release", "notes"], IO::Memory.new, stdout, stderr)

      code.should eq(0)
      stdout.to_s.should contain("created TODO: #{todo_path}")
      File.read(todo_path).should eq("* Notes\n** TODO write release notes\n")
    end
  end

  it "shows multiple configured @ actions and uses the selected one" do
    with_fake_fzf do |root, _bin|
      inbox_path = File.join(root, "notes", "inbox.org")
      project_path = File.join(root, "notes", "project.org")
      FileUtils.mkdir_p(Actra::Xdg.astra_config_dir)
      File.write(Actra::Xdg.astra_config_path, %(
        at do
          action "inbox" do
            label = "Add to Inbox"
            kind = "org_todo"
            org_todo_path = "#{inbox_path}"
            category = "Inbox"
          end

          action "project" do
            label = "Add to Project"
            kind = "org_todo"
            org_todo_path = "#{project_path}"
            category = "Project"
          end
        end
      ))

      stdout = IO::Memory.new
      stderr = IO::Memory.new
      code = Actra::CLI.run(["@", "Add to Project", "ship", "feature"], IO::Memory.new, stdout, stderr)

      code.should eq(0)
      File.exists?(inbox_path).should be_false
      File.read(project_path).should eq("* Project\n** TODO ship feature\n")
    end
  end

  it "rejects configured actions without text" do
    with_fake_fzf do |root, _bin|
      todo_path = File.join(root, "notes", "tasks.org")
      FileUtils.mkdir_p(Actra::Xdg.astra_config_dir)
      File.write(Actra::Xdg.astra_config_path, %(
        at do
          action "inbox" do
            label = "Add to Inbox"
            kind = "org_todo"
            org_todo_path = "#{todo_path}"
            category = "Inbox"
          end
        end
      ))

      stdout = IO::Memory.new
      stderr = IO::Memory.new
      code = Actra::CLI.run(["@", "Add to Inbox"], IO::Memory.new, stdout, stderr)

      code.should eq(1)
      stderr.to_s.should contain("missing text for action")
      File.exists?(todo_path).should be_false
    end
  end

  it "opens a selected file with the configured filetype editor" do
    with_fake_fzf("open in editor") do |root, bin|
      opened = File.join(root, "opened.txt")
      editor = File.join(bin, "fake-editor")
      File.write(editor, <<-SH)
        #!/bin/sh
        printf '%s\\n' "$@" > #{opened}
        SH
      File.chmod(editor, 0o755)

      FileUtils.mkdir_p(Actra::Xdg.astra_config_dir)
      File.write(Actra::Xdg.astra_config_path, %(
        filetype "crystal" do
          extensions = [".cr"]
          editor = "#{editor} --line {}"
        end
      ))

      stdout = IO::Memory.new
      stderr = IO::Memory.new
      code = Actra::CLI.run(["@", "@src/demo.cr"], IO::Memory.new, stdout, stderr)
      absolute = File.join(root, "src", "demo.cr")

      code.should eq(0)
      File.read(opened).should eq("--line\n#{absolute}\n")
    end
  end

  it "labels the open action with the selected filetype editor" do
    with_fake_fzf("open with fake-editor") do |root, bin|
      FileUtils.mkdir_p(File.join(root, "src"))
      File.write(File.join(root, "src", "demo.cr"), "")

      opened = File.join(root, "opened.txt")
      editor = File.join(bin, "fake-editor")
      File.write(editor, <<-SH)
        #!/bin/sh
        printf '%s\\n' "$@" > #{opened}
        SH
      File.chmod(editor, 0o755)

      Dir.cd(root) do
        FileUtils.mkdir_p(Actra::Xdg.astra_config_dir)
        File.write(Actra::Xdg.astra_config_path, %(
          filetype "crystal" do
            extensions = [".cr"]
            editor = "#{editor} --line {}"
          end
        ))

        stdout = IO::Memory.new
        stderr = IO::Memory.new
        code = Actra::CLI.run(["@", "@src/demo.cr"], IO::Memory.new, stdout, stderr)
        absolute = File.join(root, "src", "demo.cr")

        code.should eq(0)
        File.read(opened).should eq("--line\n#{absolute}\n")
      end
    end
  end
end
