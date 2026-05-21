require "../openapi/loader"
require "../openapi/compat"

module Actra
  module Plugins
    module OasValidate
      def self.run(argv : Array(String), stdout : IO, stderr : IO) : Int32
        path_or_url = argv[0]?
        unless path_or_url
          stderr.puts "missing <file_or_url>"
          return 1
        end

        begin
          doc = OpenAPI::Loader.load_any(path_or_url)
          report = OpenAPI::Compat.validate(doc)
          stdout.puts report.to_text
          return report.exit_code
        rescue ex : OpenAPI::UnsupportedVersionError
          stdout.puts "ok: false\nerrors:\n  - #{ex.message}"
          return 2
        rescue ex
          stderr.puts ex.message
          return 3
        end
      end
    end
  end
end

