require "spec"

require "../src/actra/render/engine"
require "../src/actra/render/config"

describe Actra::Render::Engine do
  it "renders an array of objects as a table" do
    bytes = %([{"a":1,"b":"x"},{"a":2,"b":"y"}]).to_slice
    out_io = IO::Memory.new
    Actra::Render::Engine.render(bytes, Actra::Render::Mode::Table, out_io, Actra::Render::Config.default)
    s = out_io.to_s
    s.should contain("a")
    s.should contain("b")
    s.should contain("1")
    s.should contain("x")
  end

  it "renders an object as pretty json in auto mode" do
    bytes = %({"a":1,"b":{"c":2}}).to_slice
    out_io = IO::Memory.new
    Actra::Render::Engine.render(bytes, Actra::Render::Mode::Auto, out_io, Actra::Render::Config.default)
    out_io.to_s.should contain(%(\n  "b": {\n))
  end
end
