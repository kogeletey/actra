module Actra
  module Rcl
    alias Scalar = String | Float64 | Bool
    alias Value = Scalar | Array(Scalar)

    class Error < Exception
    end

    class Block
      getter name : String
      getter argument : String?
      getter properties : Hash(String, Value)
      getter blocks : Array(Block)

      def initialize(@name : String, @argument : String? = nil)
        @properties = {} of String => Value
        @blocks = [] of Block
      end
    end

    class Document
      getter blocks : Array(Block)

      def initialize(@blocks : Array(Block))
      end

      def first_block(name : String) : Block?
        blocks.find { |block| block.name == name }
      end

      def blocks_named(name : String) : Array(Block)
        blocks.select { |block| block.name == name }
      end
    end

    def self.parse(text : String) : Document
      root = Block.new("__root__")
      stack = [root]

      text.lines.each_with_index do |raw_line, index|
        line = strip_comment(raw_line).strip
        next if line.empty?

        if line == "end"
          raise Error.new("unexpected end at line #{index + 1}") if stack.size == 1
          stack.pop
          next
        end

        if match = line.match(/^([A-Za-z_][A-Za-z0-9_-]*)(?:\s+"([^"]+)")?\s+do$/)
          block = Block.new(match[1], match[2]?)
          stack.last.blocks << block
          stack << block
          next
        end

        if match = line.match(/^([A-Za-z_][A-Za-z0-9_.-]*)\s*=\s*(.+)$/)
          key = match[1]
          value = parse_value(match[2].strip, index + 1)
          stack.last.properties[key] = value
          next
        end

        raise Error.new("invalid RCL statement at line #{index + 1}: #{line}")
      end

      raise Error.new("missing end for #{stack.last.name}") if stack.size > 1
      Document.new(root.blocks)
    end

    private def self.strip_comment(line : String) : String
      in_string = false
      escaped = false

      line.each_char_with_index do |char, index|
        if escaped
          escaped = false
          next
        end

        if char == '\\'
          escaped = true
          next
        end

        if char == '"'
          in_string = !in_string
          next
        end

        return line[0, index] if char == '#' && !in_string
      end

      line
    end

    private def self.parse_value(raw : String, line : Int32) : Value
      if raw.starts_with?("[") && raw.ends_with?("]")
        return parse_array(raw[1, raw.size - 2], line)
      end

      parse_scalar(raw, line)
    end

    private def self.parse_scalar(raw : String, line : Int32) : Scalar
      if raw.starts_with?('"') && raw.ends_with?('"') && raw.size >= 2
        return unquote(raw)
      end

      case raw
      when "true"
        return true
      when "false"
        return false
      end

      if raw.match(/^-?\d+(?:\.\d+)?$/)
        return raw.to_f64
      end

      raise Error.new("invalid value at line #{line}: #{raw}")
    end

    private def self.parse_array(raw : String, line : Int32) : Array(Scalar)
      values = [] of Scalar
      current = String::Builder.new
      in_string = false
      escaped = false

      raw.each_char do |char|
        if escaped
          current << char
          escaped = false
          next
        end

        if char == '\\'
          current << char
          escaped = true
          next
        end

        if char == '"'
          current << char
          in_string = !in_string
          next
        end

        if char == ',' && !in_string
          item = current.to_s.strip
          values << parse_scalar(item, line) unless item.empty?
          current = String::Builder.new
          next
        end

        current << char
      end

      item = current.to_s.strip
      values << parse_scalar(item, line) unless item.empty?
      values
    end

    private def self.unquote(raw : String) : String
      raw[1, raw.size - 2]
        .gsub("\\\"", "\"")
        .gsub("\\n", "\n")
        .gsub("\\t", "\t")
        .gsub("\\\\", "\\")
    end
  end
end
