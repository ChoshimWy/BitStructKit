Pod::Spec.new do |spec|
  spec.name         = "BitStructKit"
  spec.version      = "0.1.0"
  spec.summary      = "Declarative bit-field encoder/decoder for Swift structs."
  spec.description  = <<-DESC
BitStructKit provides a lightweight protocol for describing bit-packed network or firmware
payloads. Declare your fields with widths, then encode/decode Data buffers with the
same layout you would expect from C bitfields.
  DESC
  spec.homepage     = "https://github.com/ChoshimWy/BitStructKit"
  spec.license      = { :type => "MIT" }
  spec.authors      = { "ChoshimWei" => "" }
  spec.swift_versions = ["5"]
  spec.ios.deployment_target = "11.0"
  spec.osx.deployment_target = "10.15"
  spec.source       = { :git => "https://github.com/ChoshimWy/BitStructKit.git", :tag => spec.version }
  spec.source_files = "Sources/BitStructKit/**/*.{swift}"
  spec.requires_arc = true
end
