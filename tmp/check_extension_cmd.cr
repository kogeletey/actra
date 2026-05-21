require "../src/actra/extensions"
require "../src/actra/config"

runtime = Actra::ExtensionRuntime.for_config(Actra::Config.load, ["/tmp/rewrite.cr"], true)
extensions = runtime.instance_variable_get("@extensions")
ext = extensions[0]
puts ext.name
puts ext.command
puts ext.events.inspect
