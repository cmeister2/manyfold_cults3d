# frozen_string_literal: true

require "time"
require "uri"

module ManyfoldCults3d
  class Inventory
    class Error < StandardError; end
    MAX_ITEMS = 20_000

    def self.attributes(orders)
      invalid! unless orders.is_a?(Array) && orders.length <= MAX_ITEMS
      models = {}
      orders.each do |order|
        invalid! unless order.is_a?(Hash) && order["lines"].is_a?(Array) && order["lines"].length <= 1000
        order_id = text!(order["id"], 128)
        added_at = timestamp!(order["createdAt"])
        order["lines"].each do |line|
          invalid! unless line.is_a?(Hash) && line["creation"].is_a?(Hash)
          creation = line["creation"]
          source = Source.new(text!(creation["identifier"], 128))
          invalid! unless source.identifier
          id = source.identifier
          slug = text!(creation["slug"], 512)
          url = Source.canonical_url(creation)
          name = text!(creation["name"], 1024)
          invalid! if name.length > 255
          creator = creation["creator"]
          invalid! unless creator.nil? || creator.is_a?(Hash)
          creator ||= {}
          record = {
            cults3d_id: id, slug: slug, url: url, name: name,
            tags: tags!(creation["tags"]), sources: ["ORDER"],
            published_at: timestamp!(creation["publishedAt"]),
            creator_name: optional_text!(creator["nick"], 512),
            creator_username: optional_text!(creator["nick"], 512),
            creator_avatar: optional_text!(creator["imageUrl"], 4096),
            library_added_at: added_at,
            library_entries: [{
              "order_id" => order_id, "line_id" => text!(line["id"], 128),
              "library_added_at" => added_at&.iso8601,
              "download_url" => download_url!(line["downloadUrl"])
            }]
          }
          previous = models[id]
          if previous
            latest = added_at && (previous[:library_added_at].nil? || added_at > previous[:library_added_at])
            record = (latest ? record : previous).merge(
              tags: (previous[:tags] + record[:tags]).uniq,
              library_entries: (previous[:library_entries] + record[:library_entries]).uniq
            )
            invalid! if record[:tags].length > 128
          end
          models[id] = record
          invalid! if models.length > MAX_ITEMS
        end
      end
      models.values
    rescue Source::Invalid, URI::InvalidURIError, ArgumentError
      invalid!
    end

    def self.text!(value, max_bytes)
      invalid! unless value.is_a?(String) && value.valid_encoding? && value.bytesize <= max_bytes &&
        !value.match?(/[[:cntrl:]]/) && !value.strip.empty?
      value.strip
    end
    private_class_method :text!

    def self.optional_text!(value, max_bytes)
      return nil if value.nil? || (value.is_a?(String) && value.strip.empty?)
      text!(value, max_bytes)
    end
    private_class_method :optional_text!

    def self.tags!(value)
      invalid! unless value.is_a?(Array) && value.length <= 128
      value.map { |tag| text!(tag, 256) }.uniq
    end
    private_class_method :tags!

    def self.timestamp!(value)
      return nil if value.nil?
      invalid! unless value.is_a?(String) && value.bytesize <= 64 &&
        value.match?(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:?\d{2})\z/)
      Time.iso8601(value).utc
    end
    private_class_method :timestamp!

    def self.download_url!(value)
      return nil if value.nil?
      uri = URI.parse(text!(value, 4096))
      invalid! unless uri.is_a?(URI::HTTPS) && uri.host == "cults3d.com" &&
        uri.port == 443 && !uri.userinfo && uri.path.match?(%r{\A/[a-z]{2}/downloads/[1-9][0-9]*/?\z})
      uri.to_s
    end
    private_class_method :download_url!

    def self.invalid!
      raise Error, "Cults3D returned invalid library data. Your saved library has not changed."
    end
    private_class_method :invalid!
  end
end
