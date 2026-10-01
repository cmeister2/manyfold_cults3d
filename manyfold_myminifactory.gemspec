# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name = "manyfold_myminifactory"
  spec.version = "0.1.0"
  spec.authors = ["Max Dymond"]
  spec.summary = "MyMiniFactory integration"
  spec.description = "MyMiniFactory integration"
  spec.homepage = "https://github.com/cmeister2/manyfold_myminifactory"
  spec.metadata["manyfold_version"] = ">= 0.146.0"
  spec.files = Dir["app/**/*", "config/**/*", "lib/**/*"]
  spec.require_paths = ["lib"]
end
