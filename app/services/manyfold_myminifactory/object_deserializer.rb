# frozen_string_literal: true

module ManyfoldMyminifactory
  class ObjectDeserializer < ::Integrations::MyMiniFactory::BaseDeserializer
    def initialize(payload:)
      @mapper = MetadataMapper.new(payload)
      @uri = Source.canonical_url(payload)
    end

    def deserialize
      attributes = @mapper.attributes.merge(
        file_urls: @mapper.file_urls,
        preview_filename: @mapper.images.find { |image| image[:primary] }&.dig(:filename)
      )
      designer = @mapper.designer
      attributes.merge!(creator_attributes(designer)) if designer
      attributes
    end
  end
end
