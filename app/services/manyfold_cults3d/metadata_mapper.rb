# frozen_string_literal: true

require "cgi"
require "uri"
require "reverse_markdown"
require "spdx"

module ManyfoldCults3d
  class MetadataMapper
    def initialize(payload)
      @payload = payload
    end

    def attributes
      {
        name: text(@payload["name"]),
        notes: description,
        tag_list: tags,
        license: license,
        sensitive: (@payload["safe"] == false if [true, false].include?(@payload["safe"]))
      }.reject { |_key, value| value.nil? || (value.respond_to?(:empty?) && value.empty?) }
    end

    def designer
      raw = @payload["creator"]
      return unless raw.is_a?(Hash)
      username = text(raw["nick"])
      return unless username && username.parameterize.present?

      {
        "name" => username,
        "username" => username,
        "bio" => text(raw["bio"]) || "",
        "profile_url" => creator_url(raw["url"]) ||
          "https://cults3d.com/en/users/#{URI.encode_www_form_component(username).gsub('+', '%20')}",
        "avatar_url" => image_uri(text(raw["imageUrl"]))&.to_s
      }
    end

    def images
      primary = image_uri(text(@payload["illustrationImageUrl"]))&.to_s
      illustrations = @payload["illustrations"].is_a?(Array) ? @payload["illustrations"] : []
      descriptors = illustrations.filter_map do |image|
        next unless image.is_a?(Hash)
        uri = image_uri(text(image["imageUrl"]))
        next unless uri
        filename = safe_filename(uri.path)
        next unless filename

        position = image["position"]
        {id: image["id"], url: uri.to_s, filename: filename, primary: uri.to_s == primary,
         position: position.is_a?(Integer) ? position : nil}
      end.sort_by { |image| image[:position] || Float::INFINITY }.uniq { |image| image[:url] }
      if primary && descriptors.none? { |image| image[:primary] }
        filename = safe_filename(URI.parse(primary).path)
        descriptors.unshift({url: primary, filename: filename, primary: true}) if filename
      end
      descriptors.first[:primary] = true if descriptors.any? && descriptors.none? { |image| image[:primary] }
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
      parts = []
      description = markdown(@payload["description"])
      parts << description if description
      details = markdown(@payload["details"])
      parts << "## Printing settings\n\n#{details}" if details && details != description
      text(parts.join("\n\n"))
    end

    def markdown(value)
      value = text(value)
      return unless value
      return value unless value.match?(/<\/?[a-z][^>]*>/i)

      converted = text(ReverseMarkdown.convert(value))
      converted if converted && text(Nokogiri::HTML.fragment(converted).text)
    end

    def tags
      return [] unless @payload["tags"].is_a?(Array)
      @payload["tags"].filter_map { |tag| text(tag) }.uniq
    end

    def license
      raw = @payload["license"]
      candidate = text(raw["spdxId"]) if raw.is_a?(Hash)
      return unless candidate && candidate.match?(/\A[A-Za-z0-9][A-Za-z0-9.+-]*\z/)
      candidate if Spdx.valid?(candidate)
    end

    def creator_url(value)
      uri = https_uri(text(value))
      return unless uri && Source::HOSTS.include?(uri.host.downcase) && uri.path.match?(%r{\A/[a-z]{2}(?:-[a-z]{2})?/(?:users|benutzer|usuarios|utilisateurs|polzovateli|y%C3%B2ngh%C3%B9)/[^/]+/?\z}i)
      uri.host = "cults3d.com"
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

    def image_uri(value)
      uri = https_uri(value)
      return unless uri
      # Cults' LARGE image URLs wrap the original URL in a resize proxy.
      # DEFAULT image URLs are already original assets.
      if uri.host.downcase == "images.cults3d.com" && value.include?("()/")
        https_uri(value.split("()/").last)
      else
        uri
      end
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
