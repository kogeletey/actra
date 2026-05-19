require "spec"
require "file_utils"

require "./support/tmpdir"
require "../src/actra/cli"
require "../src/actra/interactive/prompt"

private def with_fake_fzf(action : String, &)
  SpecTmpdir.with do |root|
    bin = File.join(root, "bin")
    FileUtils.mkdir_p(bin)
    fzf = File.join(bin, "fzf")
    File.write(fzf, <<-SH)
      #!/bin/sh
      case "$*" in
        *"File action>"*) printf '%s\\n' "$ACTRA_TEST_FZF_ACTION" ;;
        *) printf 'src/demo.cr\\n' ;;
      esac
      SH
    File.chmod(fzf, 0o755)

    FileUtils.mkdir_p(File.join(root, "src"))
    File.write(File.join(root, "src", "demo.cr"), "")

    old_path = ENV["PATH"]?
    old_root = ENV["ACTRA_TEST_ROOT"]?
    ENV["PATH"] = "#{bin}:#{old_path}"
    ENV["ACTRA_TEST_ROOT"] = root
    ENV["ACTRA_TEST_FZF_ACTION"] = action
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
    end
  end
end

describe Actra::Interactive::PickerFzf do
  it "formats selected files as shell-safe context tokens" do
    tokens = Actra::Interactive::PickerFzf.context_tokens(["./src/actra/cli.cr", "docs/file name.md"])

    tokens.should eq("'@src/actra/cli.cr' '@docs/file name.md'")
  end

  it "lists @file context candidates for shell completion" do
    SpecTmpdir.with do |root|
      FileUtils.mkdir_p(File.join(root, "src"))
      File.write(File.join(root, "src", "demo.cr"), "")

      Dir.cd(root) do
        candidates = Actra::Interactive::PickerFzf.file_context_candidates("@src")
        candidates.should contain("@src/demo.cr")
      end
    end
  end

  it "opens a file action menu before printing an @file attachment" do
    with_fake_fzf("attach @file") do
      stdout = IO::Memory.new
      stderr = IO::Memory.new

      code = Actra::CLI.run(["@file"], IO::Memory.new, stdout, stderr)

      code.should eq(0)
      stdout.to_s.should eq("'@src/demo.cr'\n")
    end
  end

  it "copies an absolute path from the @file action menu" do
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
      code = Actra::CLI.run(["@file"], IO::Memory.new, stdout, stderr)
      absolute = File.join(root, "src", "demo.cr")

      code.should eq(0)
      File.read(copy_out).should eq(absolute)
      stdout.to_s.should eq("#{absolute}\n")
      stderr.to_s.should contain("copied absolute path")
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
      code = Actra::CLI.run(["@file"], IO::Memory.new, stdout, stderr)
      absolute = File.join(root, "src", "demo.cr")

      code.should eq(0)
      File.read(opened).should eq("--line\n#{absolute}\n")
    end
  end
end
