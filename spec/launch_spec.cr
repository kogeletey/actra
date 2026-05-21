require "spec"
require "file_utils"

require "./support/tmpdir"
require "../src/actra/cli"
require "../src/actra/xdg"

private def with_launch_temp_root(&)
  SpecTmpdir.with do |root|
    ENV["ACTRA_TEST_ROOT"] = root
    begin
      yield root
    ensure
      ENV.delete("ACTRA_TEST_ROOT")
    end
  end
end

describe "launch mode" do
  it "prints a background launch plan" do
    with_launch_temp_root do
      stdout = IO::Memory.new
      stderr = IO::Memory.new
      code = Actra::CLI.run(["launch", "--mode", "background", "--dry-run", "printf", "ok"], IO::Memory.new, stdout, stderr)

      code.should eq(0)
      stdout.to_s.should contain("nohup 'printf' 'ok'")
      stdout.to_s.should contain("log:")
      stdout.to_s.should contain("pid:")
    end
  end

  it "supports @ as the command action menu entrypoint" do
    with_launch_temp_root do
      stdout = IO::Memory.new
      stderr = IO::Memory.new
      code = Actra::CLI.run(["@", "--action", "background", "--dry-run", "printf", "ok"], IO::Memory.new, stdout, stderr)

      code.should eq(0)
      stdout.to_s.should contain("nohup 'printf' 'ok'")
    end
  end

  it "passes a command path and command line to the assistant mode" do
    stdout = IO::Memory.new
    stderr = IO::Memory.new
    code = Actra::CLI.run(["@", "--action", "assistant", "--dry-run", "printf", "ok"], IO::Memory.new, stdout, stderr)

    code.should eq(0)
    stdout.to_s.should contain("ASSISTANT")
    stdout.to_s.should contain("Command path:")
    stdout.to_s.should contain("Command line: 'printf' 'ok'")
  end

  it "can dry-run a local command without backgrounding it" do
    stdout = IO::Memory.new
    stderr = IO::Memory.new
    code = Actra::CLI.run(["@", "--action", "run", "--dry-run", "printf", "ok"], IO::Memory.new, stdout, stderr)

    code.should eq(0)
    stdout.to_s.should contain("'printf' 'ok'")
  end

  it "runs a plain @ executable locally when there are no @ results" do
    with_launch_temp_root do |root|
      bin = File.join(root, "bin")
      FileUtils.mkdir_p(bin)
      command = File.join(bin, "go")
      File.write(command, "#!/bin/sh\nprintf 'local go\\n'\n")
      File.chmod(command, 0o755)
      old_path = ENV["PATH"]?
      ENV["PATH"] = "#{bin}:#{old_path}"
      begin
        stdout = IO::Memory.new
        stderr = IO::Memory.new
        code = Actra::CLI.run(["@", "go"], IO::Memory.new, stdout, stderr)

        code.should eq(0)
        stdout.to_s.should eq("local go\n")
        stderr.to_s.should eq("")
      ensure
        if old_path
          ENV["PATH"] = old_path
        else
          ENV.delete("PATH")
        end
      end
    end
  end

  it "supports ?tool launch as an explicit subcommand" do
    with_launch_temp_root do
      stdout = IO::Memory.new
      stderr = IO::Memory.new
      code = Actra::CLI.run(["?printf", "launch", "--mode", "background", "--dry-run", "ok"], IO::Memory.new, stdout, stderr)

      code.should eq(0)
      stdout.to_s.should contain("nohup 'printf' 'ok'")
    end
  end

  it "prints a container launch plan" do
    stdout = IO::Memory.new
    stderr = IO::Memory.new
    code = Actra::CLI.run(["launch", "--mode", "container", "--image", "alpine:latest", "--dry-run", "printf", "ok"], IO::Memory.new, stdout, stderr)

    code.should eq(0)
    stdout.to_s.should contain("'docker' 'run' '--rm' '-i'")
    stdout.to_s.should contain("'alpine:latest' 'printf' 'ok'")
  end

  it "prints a remote Lefine launch dry-run" do
    with_launch_temp_root do
      stdout = IO::Memory.new
      stderr = IO::Memory.new
      code = Actra::CLI.run(["launch", "--mode", "remote-lefine", "--dry-run", "printf", "ok"], IO::Memory.new, stdout, stderr)

      code.should eq(0)
      stdout.to_s.should contain("POST https://lefine.pro/inbox/code")
      stdout.to_s.should contain("Run this tool remotely with Lefine.")
      stdout.to_s.should contain("'printf' 'ok'")
    end
  end
end
