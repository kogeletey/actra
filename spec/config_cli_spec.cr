require "spec"
require "file_utils"

require "./support/tmpdir"
require "../src/actra/cli"

describe "config CLI" do
  it "migrates legacy astra config to the current actra path" do
    SpecTmpdir.with do |root|
      ENV["ACTRA_TEST_ROOT"] = root
      begin
        FileUtils.mkdir_p(Actra::Xdg.legacy_astra_config_dir)
        File.write(Actra::Xdg.legacy_astra_config_path, %(base do\n  default_server = "legacy.example"\nend\n))

        stdout = IO::Memory.new
        stderr = IO::Memory.new
        code = Actra::CLI.run(["config", "migrate"], IO::Memory.new, stdout, stderr)

        code.should eq(0)
        stdout.to_s.should contain("migrated:")
        File.exists?(Actra::Xdg.config_path).should be_true
        Actra::Config.load.default_server.should eq("legacy.example")
      ensure
        ENV.delete("ACTRA_TEST_ROOT")
      end
    end
  end

  it "keeps an existing current config during config update" do
    SpecTmpdir.with do |root|
      ENV["ACTRA_TEST_ROOT"] = root
      begin
        FileUtils.mkdir_p(Actra::Xdg.config_dir)
        FileUtils.mkdir_p(Actra::Xdg.legacy_astra_config_dir)
        File.write(Actra::Xdg.config_path, %(base do\n  default_server = "current.example"\nend\n))
        File.write(Actra::Xdg.legacy_astra_config_path, %(base do\n  default_server = "legacy.example"\nend\n))

        stdout = IO::Memory.new
        stderr = IO::Memory.new
        code = Actra::CLI.run(["config", "update"], IO::Memory.new, stdout, stderr)

        code.should eq(0)
        stdout.to_s.should contain("config already current:")
        Actra::Config.load.default_server.should eq("current.example")
      ensure
        ENV.delete("ACTRA_TEST_ROOT")
      end
    end
  end

  it "prints permission mode and tool rules" do
    SpecTmpdir.with do |root|
      ENV["ACTRA_TEST_ROOT"] = root
      begin
        FileUtils.mkdir_p(Actra::Xdg.config_dir)
        File.write(Actra::Xdg.config_path, %(
          permissions do
            default_mode = "restrictive"
            sandbox = true

            tool "read" do
              allow = ["src/**"]
              ask = ["tmp/**"]
              deny = ["/etc/**"]
            end
          end
        ))

        stdout = IO::Memory.new
        stderr = IO::Memory.new
        code = Actra::CLI.run(["config", "print"], IO::Memory.new, stdout, stderr)

        code.should eq(0)
        stdout.to_s.should contain("permissions: mode=restrictive sandbox=true rules=1")
        stdout.to_s.should contain("  - read allow=src/** ask=tmp/** deny=/etc/**")
      ensure
        ENV.delete("ACTRA_TEST_ROOT")
      end
    end
  end
end
