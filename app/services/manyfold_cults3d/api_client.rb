# frozen_string_literal: true

require "base64"
require "faraday"
require "json"

module ManyfoldCults3d
  class ApiClient
    BASE_URL = "https://cults3d.com/graphql"
    PAGE_SIZE = 100
    MAX_ORDERS = 20_000
    CREATION_FIELDS = <<~GRAPHQL.freeze
      identifier slug name(locale: EN) url(locale: EN) publishedAt
      description(locale: EN) details(locale: EN) tags(locale: EN) safe
      illustrationImageUrl(version: DEFAULT)
      license { code name spdxId url }
      creator { nick bio url(locale: EN) imageUrl }
      illustrations { id imageUrl(version: DEFAULT) position }
    GRAPHQL
    LIBRARY_QUERY = <<~GRAPHQL.freeze
      query Library($limit: Int!, $offset: Int!) {
        myself {
          ordersBatch(limit: $limit, offset: $offset, sort: BY_CREATION, direction: DESC) {
            total
            results {
              id createdAt
              lines {
                id downloadUrl
                creation {
                  identifier slug name(locale: EN) url(locale: EN) publishedAt tags(locale: EN)
                  creator { nick imageUrl }
                }
              }
            }
          }
        }
      }
    GRAPHQL
    OBJECT_QUERY = <<~GRAPHQL.freeze
      query Model($slug: String!) {
        creation(slug: $slug) { #{CREATION_FIELDS} }
      }
    GRAPHQL
    IDENTIFIER_QUERY = <<~GRAPHQL.freeze
      query ModelById($identifier: String!) {
        creationsBatch(ids: [$identifier], safe: false, limit: 1) {
          total results { #{CREATION_FIELDS} }
        }
      }
    GRAPHQL

    class Error < StandardError; end
    class ConfigurationError < Error; end
    class InvalidObjectId < Error; end
    class AuthenticationError < Error; end
    class NotFound < Error; end
    class RateLimited < Error; end
    class Unavailable < Error; end
    class InvalidResponse < Error; end

    def self.username
      ENV["CULTS3D_USERNAME"].presence || SiteSettings.cults3d_api_username
    end

    def self.api_key
      ENV["CULTS3D_API_KEY"].presence || SiteSettings.cults3d_api_key
    end

    def self.configured?
      username.to_s.strip.present? && api_key.to_s.strip.present?
    end

    def initialize(username: self.class.username, api_key: self.class.api_key, connection: nil)
      @username = username.to_s.strip
      @api_key = api_key.to_s.strip
      @connection = connection
    end

    # Fetch every page before returning: a failed request must not replace a
    # saved inventory with the first part of the account's library.
    def library
      orders = []
      ids = {}
      expected_total = nil
      loop do
        data = request(LIBRARY_QUERY, {limit: PAGE_SIZE, offset: orders.length})
        account = data["myself"]
        raise AuthenticationError, "Cults3D denied access to your library. Check the username and API key." if account.nil?
        batch = account.is_a?(Hash) && account["ordersBatch"]
        invalid! unless batch.is_a?(Hash) && batch["total"].is_a?(Integer) &&
          batch["total"].between?(0, MAX_ORDERS) && batch["results"].is_a?(Array)
        expected_total ||= batch["total"]
        page = batch["results"]
        invalid! unless batch["total"] == expected_total && page.length <= PAGE_SIZE &&
          orders.length + page.length <= expected_total
        page.each do |order|
          invalid! unless order.is_a?(Hash) && order["id"].is_a?(String) &&
            !order["id"].empty? && !ids.key?(order["id"])
          ids[order["id"]] = true
        end
        orders.concat(page)
        return orders if orders.length == expected_total
        invalid! if page.empty?
      end
    end

    def object(value)
      source = begin
        Source.new(value)
      rescue Source::Invalid
        raise InvalidObjectId, "Enter a Cults3D model URL, slug or ID.", cause: nil
      end
      if source.identifier
        data = request(IDENTIFIER_QUERY, {identifier: source.identifier})
        batch = data["creationsBatch"]
        invalid! unless batch.is_a?(Hash) && batch["results"].is_a?(Array) &&
          batch["total"].is_a?(Integer) && batch["total"].between?(0, 1) &&
          batch["results"].length == batch["total"]
        payload = batch["results"].first
      else
        payload = request(OBJECT_QUERY, {slug: source.slug})["creation"]
      end
      raise NotFound, "Cults3D could not find that model." if payload.nil?
      invalid! unless payload.is_a?(Hash) && source.matches?(payload)
      payload
    end

    private

    def request(query, variables)
      if @username.empty? || @api_key.empty?
        raise ConfigurationError, "Set your Cults3D username and API key in Manyfold's integration settings."
      end
      response = connection.post(BASE_URL, JSON.generate(query: query, variables: variables), {
        "Accept" => "application/json", "Content-Type" => "application/json",
        "Authorization" => "Basic #{Base64.strict_encode64("#{@username}:#{@api_key}")}"
      })
      check_status!(response.status)
      payload = response.body
      invalid! unless payload.is_a?(Hash)
      # GraphQL can return partial data and errors together with HTTP 200.
      # Never persist a partial library or expose server error text/secrets.
      invalid! if payload.key?("errors") && (!payload["errors"].is_a?(Array) || payload["errors"].any?)
      invalid! unless payload["data"].is_a?(Hash)
      payload["data"]
    rescue Faraday::ParsingError
      raise InvalidResponse, "Cults3D returned an unreadable response.", cause: nil
    rescue Faraday::Error
      raise Unavailable, "Cults3D could not be reached. Try again later.", cause: nil
    end

    def connection
      @connection ||= Faraday.new do |builder|
        builder.options.open_timeout = 5
        builder.options.timeout = 30
        builder.response :json
      end
    end

    def invalid!
      raise InvalidResponse, "Cults3D returned an incomplete or unexpected response. Refresh your library again."
    end

    def check_status!(status)
      case status
      when 200
        nil
      when 401, 403
        raise AuthenticationError, "Cults3D denied access. Check the username, API key and model access."
      when 404
        raise NotFound, "Cults3D could not find that model."
      when 429
        raise RateLimited, "Cults3D is limiting requests. Try again later."
      else
        raise Unavailable, "Cults3D could not complete the request. Try again later."
      end
    end
  end
end
