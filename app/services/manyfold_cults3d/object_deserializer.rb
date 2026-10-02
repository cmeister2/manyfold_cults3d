# frozen_string_literal: true

module ManyfoldCults3d
  class ObjectDeserializer < ::Integrations::BaseDeserializer
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

    def valid?(for_class: nil)
      @uri.present? && (for_class.nil? || for_class == ::Model)
    end

    def capabilities
      {class: ::Model, name: true, notes: true, images: true, model_files: false,
       creator: true, tags: true, sensitive: true, license: true}
    end

    private

    def creator_attributes(designer)
      attributes = {
        name: designer.fetch("name"),
        slug: designer.fetch("username").parameterize,
        notes: designer.fetch("bio"),
        links_attributes: [{url: designer.fetch("profile_url")}]
      }
      attributes[:avatar_remote_url] = designer["avatar_url"] if designer["avatar_url"]
      attempt_creator_match(attributes)
    end
  end
end
