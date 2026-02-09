require "spec"

require "../src/wacli/render/engine"
require "../src/wacli/render/config"

describe Wacli::Render::Engine do
  it "renders an array of objects as a table" do
    bytes = %([{"a":1,"b":"x"},{"a":2,"b":"y"}]).to_slice
    out_io = IO::Memory.new
    Wacli::Render::Engine.render(bytes, Wacli::Render::Mode::Table, out_io, Wacli::Render::Config.default)
    s = out_io.to_s
    s.should contain("a")
    s.should contain("b")
    s.should contain("1")
    s.should contain("x")
  end

  it "renders an object as pretty json in auto mode" do
    bytes = %({"a":1,"b":{"c":2}}).to_slice
    out_io = IO::Memory.new
    Wacli::Render::Engine.render(bytes, Wacli::Render::Mode::Auto, out_io, Wacli::Render::Config.default)
    out_io.to_s.should contain(%(\n  "b": {\n))
  end
end
