# frozen_string_literal: true

require "faraday"

module ManyfoldMyminifactory
  class ApiClient
    BASE_URL = "https://www.myminifactory.com/api/v2/"

    class Error < StandardError; end
    class ConfigurationError < Error; end
    class InvalidObjectId < Error; end
    class AuthenticationError < Error; end
    class NotFound < Error; end
    class RateLimited < Error; end
    class Unavailable < Error; end
    class InvalidResponse < Error; end

    def initialize(api_key: SiteSettings.myminifactory_api_key, connection: nil)
      @api_key = api_key.to_s.strip
      @connection = connection
    end

    def object(id)
      object_id = id.to_s
      unless object_id.match?(/\A[1-9][0-9]{0,18}\z/) && object_id.to_i <= Source::MAX_ID
        raise InvalidObjectId, "Enter a positive MyMiniFactory object ID."
      end
      if @api_key.empty?
        raise ConfigurationError, "Set the MyMiniFactory API key in Manyfold's integration settings."
      end

      response = connection.get("objects/#{object_id}", {key: @api_key}, {"Accept" => "application/json"})
      check_status!(response.status)
      payload = response.body
      unless payload.is_a?(Hash) && payload.keys.all? { |key| key.is_a?(String) } &&
          payload["id"].to_s == object_id
        raise InvalidResponse, "MyMiniFactory returned an invalid object response."
      end
      payload
    rescue Faraday::ParsingError
      raise InvalidResponse, "MyMiniFactory returned an unreadable response.", cause: nil
    rescue Faraday::Error
      raise Unavailable, "MyMiniFactory could not be reached. Try again later.", cause: nil
    end

    private

    def connection
      @connection ||= Faraday.new(url: BASE_URL) do |builder|
        builder.options.open_timeout = 5
        builder.options.timeout = 20
        builder.response :json
      end
    end

    def check_status!(status)
      case status
      when 200
        nil
      when 401, 403
        raise AuthenticationError, "MyMiniFactory denied access. Check the API key and model access."
      when 404
        raise NotFound, "MyMiniFactory could not find that model."
      when 429
        raise RateLimited, "MyMiniFactory is limiting requests. Try again later."
      else
        raise Unavailable, "MyMiniFactory could not complete the request. Try again later."
      end
    end
  end
end
