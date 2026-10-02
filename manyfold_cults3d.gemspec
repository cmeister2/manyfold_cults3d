# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name = "manyfold_cults3d"
  spec.version = "0.0.0"
  spec.authors = ["Max Dymond"]
  spec.summary = "Cults3D integration"
  spec.description = "Cults3D integration"
  spec.homepage = "https://github.com/cmeister2/manyfold_cults3d"
  spec.metadata["manyfold_version"] = ">= 0.146.0"
  spec.files = Dir["app/**/*", "config/**/*", "db/**/*", "lib/**/*"]
  spec.require_paths = ["lib"]
end
