require "./src/actra/activation"

s = Actra::Activation.script("bash")
puts s.includes?("printf '\\e7'")
puts s.includes?("printf '\e7'")
puts s.includes?("\\e7")
puts s.includes?("printf '\\e8'")
puts s.includes?("printf '\e8'")
puts s.index("printf '\\e7'")
puts s.index("printf '\e7'")
