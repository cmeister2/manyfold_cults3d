# frozen_string_literal: true

require "uri"

module ManyfoldCults3d
  class CreatorDeserializer < ::Integrations::BaseDeserializer
    def initialize(uri:, payload: nil)
      @payload = payload
      @source = CreatorSource.new(uri)
      @uri = @source.uri
    rescue CreatorSource::Invalid
      @source = @uri = nil
    end

    def deserialize
      return {} unless valid?

      payload = @payload || ApiClient.new.creator(@source.username)
      unless @source.matches?(payload)
        raise ApiClient::InvalidResponse, "Cults3D returned an unexpected creator profile."
      end
      source = CreatorSource.from_payload(payload)
      attributes = {name: source.username, slug: source.username.parameterize,
                    links_attributes: [{url: source.uri}]}
      bio = payload["bio"]
      attributes[:notes] = bio.strip if bio.is_a?(String) && bio.valid_encoding?
      avatar = image_uri(payload["imageUrl"])
      attributes[:avatar_remote_url] = avatar.to_s if avatar
      attributes
    rescue ApiClient::Error => error
      raise if @payload

      # Native Manyfold sync jobs report Faraday errors against the profile link.
      raise Faraday::Error, error.message, cause: nil
    end

    def valid?(for_class: nil)
      ApiClient.configured? && @source.present? && (for_class.nil? || for_class == ::Creator)
    end

    def capabilities
      {class: ::Creator, name: true, slug: true, notes: true}
    end

    private

    def image_uri(value)
      return unless value.is_a?(String) && value.valid_encoding?
      uri = URI.parse(value.strip)
      uri if uri.is_a?(URI::HTTPS) && uri.host && !uri.userinfo && uri.port == 443
    rescue URI::InvalidURIError, URI::InvalidComponentError
      nil
    end
  end
end
