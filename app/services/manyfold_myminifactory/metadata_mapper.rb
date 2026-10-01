# frozen_string_literal: true

require "cgi"
require "uri"
require "reverse_markdown"
require "spdx"

module ManyfoldMyminifactory
  class MetadataMapper
    def initialize(payload)
      @payload = payload
    end

    def attributes
      {
        name: text(@payload["name"]),
        notes: description,
        tag_list: tags,
        license: license
      }.reject { |_key, value| value.nil? || (value.respond_to?(:empty?) && value.empty?) }
    end

    def designer
      raw = @payload["designer"]
      return unless raw.is_a?(Hash)
      username = text(raw["username"])
      return unless username && username.parameterize.present?

      {
        "name" => text(raw["name"]) || username,
        "username" => username,
        "bio" => text(raw["bio"]) || "",
        "profile_url" => creator_url(raw["profile_url"]) ||
          "https://www.myminifactory.com/users/#{URI.encode_www_form_component(username).gsub('+', '%20')}",
        "avatar_url" => https_uri(text(raw["avatar_url"]))&.to_s,
        "cover_url" => https_uri(text(raw["cover_url"]))&.to_s
      }
    end

    def images
      return [] unless @payload["images"].is_a?(Array)

      descriptors = @payload["images"].filter_map do |image|
        next unless image.is_a?(Hash) && image["original"].is_a?(Hash)
        uri = https_uri(text(image["original"]["url"]))
        next unless uri
        filename = safe_filename(uri.path)
        next unless filename

        {id: image["id"], url: uri.to_s, filename: filename, primary: image["is_primary"] == true}
      end.uniq { |image| image[:url] }
      unique_filenames(descriptors)
    end

    def file_urls
      images.map { |image| image.slice(:url, :filename) }
    end

    private

    def text(value)
      return unless value.is_a?(String) && value.valid_encoding?
      normalized = value.gsub(/\A[[:space:]]+|[[:space:]]+\z/, "")
      normalized unless normalized.empty?
    end

    def description
      html = text(@payload["description_html"])
      converted = text(ReverseMarkdown.convert(html)) if html
      converted = nil if converted && text(Nokogiri::HTML.fragment(converted).text).nil?
      converted || text(@payload["description"])
    end

    def tags
      return [] unless @payload["tags"].is_a?(Array)
      @payload["tags"].filter_map { |tag| text(tag) }.uniq
    end

    def license
      candidate = text(@payload["license"])
      return unless candidate && candidate.match?(/\A[A-Za-z0-9][A-Za-z0-9.+-]*\z/)
      candidate if Spdx.valid?(candidate)
    end

    def creator_url(value)
      uri = https_uri(text(value))
      return unless uri && Source::HOSTS.include?(uri.host.downcase) && uri.path.match?(%r{\A/users/[^/]+/?\z})
      uri.host = "www.myminifactory.com"
      uri.query = uri.fragment = nil
      uri.path = uri.path.delete_suffix("/")
      uri.to_s
    end

    def https_uri(value)
      return unless value
      uri = URI.parse(value)
      uri if uri.is_a?(URI::HTTPS) && uri.host && !uri.userinfo && uri.port == 443
    rescue URI::InvalidURIError, URI::InvalidComponentError
      nil
    end

    def safe_filename(value)
      decoded = CGI.unescape(value).scrub.tr("\\", "/").gsub(/[[:cntrl:]]/, "_")
      return if decoded.end_with?("/")
      filename = File.basename(decoded).gsub(/[^[:alnum:]._-]/, "_").sub(/\A\.+/, "")
      filename unless filename.empty? || filename.bytesize > 255
    end

    def unique_filenames(descriptors)
      used = {}
      next_suffix = {}
      descriptors.map do |descriptor|
        filename = descriptor[:filename]
        key = filename.downcase
        candidate = filename
        index = next_suffix.fetch(key, 2)
        while used[candidate.downcase]
          extension = File.extname(filename)
          suffix = "_#{index}"
          extension = extension.byteslice(0, 254 - suffix.bytesize).scrub("") if extension.bytesize + suffix.bytesize >= 255
          stem = File.basename(filename, File.extname(filename)).byteslice(0, 255 - extension.bytesize - suffix.bytesize).scrub("")
          candidate = "#{stem.empty? ? '_' : stem}#{suffix}#{extension}"
          index += 1
        end
        next_suffix[key] = index
        used[candidate.downcase] = true
        descriptor.merge(filename: candidate)
      end
    end
  end
end
