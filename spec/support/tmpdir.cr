require "file_utils"
require "random/secure"

module SpecTmpdir
  def self.with(prefix : String = "wacli_test", &)
    path = File.join(Dir.tempdir, "#{prefix}_#{Random::Secure.hex(8)}")
    FileUtils.mkdir_p(path)
    begin
      yield path
    ensure
      FileUtils.rm_rf(path)
    end
  end
end

