# frozen_string_literal: true

require "uri"

module ManyfoldMyminifactory
  class Source
    MAX_ID = (2**63) - 1
    HOSTS = %w[myminifactory.com www.myminifactory.com].freeze
    class Invalid < StandardError; end

    attr_reader :id

    def initialize(value)
      text = value.to_s.strip
      @id = if positive_id?(text)
        text
      else
        uri = URI.parse(text)
        match = uri.path&.match(%r{\A/object/(?:3d-print-)?[^/]+-([1-9][0-9]{0,18})/?\z})
        match[1] if valid_uri?(uri) && match && positive_id?(match[1])
      end
      raise Invalid, "Enter a MyMiniFactory model URL or numeric model ID." unless @id
    rescue URI::InvalidURIError, URI::InvalidComponentError
      raise Invalid, "Enter a MyMiniFactory model URL or numeric model ID.", cause: nil
    end

    def self.canonical_url(payload)
      uri = URI.parse(payload.fetch("url").to_s)
      source = new(uri.to_s)
      unless uri.host && source.id == payload.fetch("id").to_s
        raise Invalid, "MyMiniFactory returned an unexpected model URL."
      end

      URI::HTTPS.build(host: "www.myminifactory.com", path: uri.path.delete_suffix("/")).to_s
    rescue KeyError, URI::InvalidURIError, URI::InvalidComponentError
      raise Invalid, "MyMiniFactory returned an incomplete model URL.", cause: nil
    end

    private

    def positive_id?(value)
      value.match?(/\A[1-9][0-9]{0,18}\z/) && value.to_i <= MAX_ID
    end

    def valid_uri?(uri)
      expected_port = {"http" => 80, "https" => 443}[uri.scheme]
      expected_port && uri.port == expected_port && !uri.userinfo && HOSTS.include?(uri.host&.downcase)
    end
  end
end
