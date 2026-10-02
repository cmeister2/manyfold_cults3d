# frozen_string_literal: true

require "base64"
require "uri"

module ManyfoldCults3d
  class Source
    MAX_ID = (2**63) - 1
    MAX_SLUG_BYTES = 512
    HOSTS = %w[cults3d.com www.cults3d.com].freeze
    MODEL_PATH = %r{\A/[a-z]{2}(?:-[a-z]{2})?/(?:3d-model|modell-3d|modelo-3d|mod%C3%A8le-3d|3d-m%C3%B3x%C3%ADng)/[a-z0-9_-]+/([^/]+)/?\z}i
    MESSAGE = "Enter a Cults3D model URL, slug, numeric ID, or Creation identifier."
    class Invalid < StandardError; end

    # API identifiers encode "Creation/<number>" without Base64 padding.
    # Slugs are passed directly to creation(slug:); identifiers use creationsBatch.
    attr_reader :id, :identifier, :numeric_id, :slug

    def initialize(value)
      text = value.to_s.strip
      raise Invalid, MESSAGE unless text.valid_encoding? && text.bytesize.between?(1, 4096)

      @numeric_id = self.class.numeric_id(text) || self.class.decode_identifier(text)
      if @numeric_id
        @identifier = Base64.strict_encode64("Creation/#{@numeric_id}").delete("=")
      elsif text.match?(%r{\Ahttps?://}i)
        parse_url(text)
      elsif self.class.valid_slug?(text) && !text.match?(/\A[0-9]+\z/) && !self.class.other_global_identifier?(text)
        @slug = text
      end
      @id = @identifier || (@slug&.match?(/\A[0-9]+\z/) ? text : @slug)
      raise Invalid, MESSAGE unless @id
    rescue URI::InvalidURIError, URI::InvalidComponentError, ArgumentError
      raise Invalid, MESSAGE, cause: nil
    end

    def matches?(payload)
      return false unless payload.is_a?(Hash)
      return false unless payload["identifier"].is_a?(String) && self.class.decode_identifier(payload["identifier"])
      payload_identifier = self.class.identifier_for(payload["identifier"])
      if identifier
        identifier == payload_identifier
      else
        slug == payload["slug"]
      end
    rescue Invalid
      false
    end

    def self.identifier_for(value)
      source = new(value)
      source.identifier || raise(Invalid, MESSAGE)
    end

    def self.numeric_id_for(value)
      source = new(value)
      source.numeric_id || raise(Invalid, MESSAGE)
    end

    def self.canonical_url(payload)
      raise Invalid, "Cults3D returned an incomplete model URL." unless payload.is_a?(Hash)
      url = payload.fetch("url")
      uri = URI.parse(url)
      source = new(url)
      raise Invalid, "Cults3D returned an unexpected model URL." unless valid_uri?(uri)
      raise Invalid, "Cults3D returned an invalid model identifier." unless payload["identifier"].is_a?(String) && decode_identifier(payload["identifier"])

      if source.slug
        raise Invalid, "Cults3D returned an unexpected model URL." unless source.slug == payload.fetch("slug")
      elsif !source.matches?(payload)
        raise Invalid, "Cults3D returned an unexpected model URL."
      end

      if payload["shortUrl"]
        short_source = new(payload["shortUrl"])
        unless short_source.identifier && short_source.matches?(payload)
          raise Invalid, "Cults3D returned an unexpected short URL."
        end
      end
      URI::HTTPS.build(host: "cults3d.com", path: uri.path.delete_suffix("/")).to_s
    rescue KeyError, TypeError, URI::InvalidURIError, URI::InvalidComponentError
      raise Invalid, "Cults3D returned an incomplete model URL.", cause: nil
    end

    def self.numeric_id(value)
      value if value.match?(/\A[1-9][0-9]{0,18}\z/) && value.to_i <= MAX_ID
    end

    def self.decode_identifier(value)
      return unless value.is_a?(String) && value.valid_encoding? && value.bytesize <= 128
      decoded = decode_base64(value)
      numeric_id(decoded.delete_prefix("Creation/")) if decoded&.start_with?("Creation/")
    end

    def self.valid_slug?(value)
      value.is_a?(String) && value.valid_encoding? && value.bytesize.between?(1, MAX_SLUG_BYTES) &&
        value.match?(/\A[[:alnum:]][[:alnum:]_-]*\z/)
    end

    def self.valid_uri?(uri)
      uri.is_a?(URI::HTTPS) && uri.port == 443 && !uri.userinfo && HOSTS.include?(uri.host&.downcase)
    end

    def self.other_global_identifier?(value)
      decoded = decode_base64(value)
      decoded && decoded.valid_encoding? && decoded.match?(%r{\A[A-Z][A-Za-z]*/})
    end

    def self.decode_base64(value)
      return unless value.match?(/\A[A-Za-z0-9+\/]+={0,2}\z/) && value.length % 4 != 1
      unpadded = value.delete_suffix("==").delete_suffix("=")
      Base64.strict_decode64(unpadded + "=" * ((4 - unpadded.length % 4) % 4))
    rescue ArgumentError
      nil
    end
    private_class_method :decode_base64

    private

    def parse_url(text)
      uri = URI.parse(text)
      return unless self.class.valid_uri?(uri)

      if (match = uri.path.match(%r{\A/:([1-9][0-9]{0,18})/?\z}))
        @numeric_id = self.class.numeric_id(match[1])
        @identifier = Base64.strict_encode64("Creation/#{@numeric_id}").delete("=") if @numeric_id
      elsif (match = uri.path.match(MODEL_PATH))
        candidate = URI::DEFAULT_PARSER.unescape(match[1]).force_encoding(Encoding::UTF_8)
        @slug = candidate if self.class.valid_slug?(candidate)
      end
    end
  end
end
