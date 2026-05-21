require "spec"
require "file_utils"

require "./support/tmpdir"
require "../src/actra/cli"

describe "config CLI" do
  it "prints permission mode and tool rules" do
    SpecTmpdir.with do |root|
      ENV["ACTRA_TEST_ROOT"] = root
      begin
        FileUtils.mkdir_p(Actra::Xdg.astra_config_dir)
        File.write(Actra::Xdg.astra_config_path, %(
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
