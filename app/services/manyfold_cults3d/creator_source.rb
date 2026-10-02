# frozen_string_literal: true

require "uri"

module ManyfoldCults3d
  class CreatorSource
    MAX_USERNAME_BYTES = 512
    PROFILE_PATH = %r{\A/[a-z]{2}(?:-[a-z]{2})?/(?:users|benutzer|usuarios|utilisateurs|polzovateli|y%C3%B2ngh%C3%B9)/([^/]+)(?:/(?:3d-models|3d-modelle|modelos-3d|fichiers-3d|3d-modeli|s%C4%81nw%C3%A8i-m%C3%B3-x%C3%ADng))?/?\z}i
    MESSAGE = "Enter a Cults3D creator profile URL."

    class Invalid < StandardError; end

    attr_reader :uri, :username

    def initialize(value)
      text = value.to_s.strip
      raise Invalid, MESSAGE unless text.valid_encoding? && text.bytesize.between?(1, 4096)

      parsed = URI.parse(text)
      raise Invalid, MESSAGE unless self.class.valid_uri?(parsed)
      match = parsed.path.match(PROFILE_PATH)
      raise Invalid, MESSAGE unless match

      @username = URI::DEFAULT_PARSER.unescape(match[1]).force_encoding(Encoding::UTF_8)
      raise Invalid, MESSAGE unless self.class.valid_username?(@username)

      @uri = self.class.profile_url(@username)
    rescue URI::InvalidURIError, URI::InvalidComponentError, ArgumentError
      raise Invalid, MESSAGE, cause: nil
    end

    def matches?(payload)
      other = self.class.from_payload(payload)
      username.casecmp?(other.username)
    rescue Invalid
      false
    end

    def self.from_payload(payload)
      raise Invalid, "Cults3D returned an incomplete creator profile." unless payload.is_a?(Hash) &&
        valid_username?(payload["nick"]) && payload["url"].is_a?(String)

      source = new(payload["url"])
      unless source.username.casecmp?(payload["nick"])
        raise Invalid, "Cults3D returned an unexpected creator profile."
      end
      new(profile_url(payload["nick"]))
    end

    def self.linked?(creator)
      creator.links.any? do |link|
        new(link.url)
        true
      rescue Invalid
        false
      end
    end

    def self.valid_username?(value)
      value.is_a?(String) && value.valid_encoding? && value.bytesize.between?(1, MAX_USERNAME_BYTES) &&
        value.match?(/\A[[:alnum:] _-]+\z/) && value == value.strip && value.parameterize.present?
    end

    def self.valid_uri?(value)
      (value.is_a?(URI::HTTPS) && value.port == 443 || value.is_a?(URI::HTTP) && value.scheme == "http" && value.port == 80) &&
        !value.userinfo && Source::HOSTS.include?(value.host&.downcase)
    end

    def self.profile_url(username)
      "https://cults3d.com/en/users/#{URI.encode_www_form_component(username).gsub('+', '%20')}"
    end
  end
end
