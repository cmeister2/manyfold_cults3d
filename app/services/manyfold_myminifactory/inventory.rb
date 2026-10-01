# frozen_string_literal: true

require "date"
require "json"
require "time"

module ManyfoldMyminifactory
  class Inventory
    class Error < StandardError; end

    MAX_ID = (2**63) - 1

    def self.parse(json)
      invalid! unless json.is_a?(String) && json.bytesize <= 5 * 1024 * 1024
      previews = JSON.parse(json)
      invalid! unless previews.is_a?(Array) && previews.length <= 20_000

      models = {}
      previews.each do |preview|
        invalid! unless preview.is_a?(Hash) && preview["type"].is_a?(String) &&
          preview["type"].match?(/\A[a-zA-Z][a-zA-Z0-9_-]{0,63}\z/)
        next unless preview["type"] == "object"

        id = model_id!(preview)
        source = text!(preview["source"], 64)
        added_at = timestamp!(preview["libraryAddedAt"])
        order = preview["order"]
        invalid! unless order.nil? || order.is_a?(Hash)
        order_id = order && order["id"]
        attributes = {
          myminifactory_id: id,
          name: text!(preview["name"], 225),
          tags: tags!(preview["tags"]),
          sources: [source],
          source_created_at: timestamp!(preview["createdAt"]),
          source_updated_at: timestamp!(preview["updatedAt"]),
          published_at: timestamp!(preview["publishedAt"]),
          creator_username: optional_text!(preview["creatorUsername"], 225),
          creator_name: optional_text!(preview["creatorName"], 225),
          creator_id: preview["creatorId"].nil? ? nil : positive_id!(preview["creatorId"]),
          creator_avatar: optional_text!(preview["creatorAvatar"], 4096),
          library_added_at: added_at,
          library_entries: [{
            "source" => source,
            "library_added_at" => added_at&.iso8601(6),
            "order_id" => order_id.nil? ? nil : positive_id!(order_id),
            "order_reference" => optional_text!(order && order["reference"], 225),
            "release" => optional_text!(preview["release"], 512)
          }]
        }
        previous = models[id]
        if previous
          tags = (previous[:tags] + attributes[:tags]).uniq
          sources = (previous[:sources] + attributes[:sources]).uniq
          entries = (previous[:library_entries] + attributes[:library_entries]).uniq
          invalid! if tags.length > 128 || sources.length > 32
          newer = added_at && (previous[:library_added_at].nil? || added_at > previous[:library_added_at])
          attributes = (newer ? attributes : previous).merge(tags: tags, sources: sources, library_entries: entries)
        end
        models[id] = attributes
      end
      models.values
    end

    def self.model_id!(preview)
      original_id = preview["originalId"]
      if original_id.nil?
        invalid! unless preview["id"].is_a?(String) && preview["id"].start_with?("object-")
        original_id = preview["id"].delete_prefix("object-")
      end
      id = positive_id!(original_id)
      invalid! if preview.key?("id") && preview["id"] != "object-#{id}"
      id
    end
    private_class_method :model_id!

    def self.positive_id!(value)
      if value.is_a?(String) && value.match?(/\A[1-9][0-9]{0,18}\z/)
        value = value.to_i
      end
      invalid! unless value.is_a?(Integer) && value.between?(1, MAX_ID)
      value
    end
    private_class_method :positive_id!

    def self.text!(value, max_bytes, empty: false)
      invalid! unless value.is_a?(String) && value.valid_encoding? &&
        value.bytesize <= max_bytes && !value.match?(/[[:cntrl:]]/)
      text = value.strip
      invalid! if text.empty? && !empty
      text
    end
    private_class_method :text!

    def self.optional_text!(value, max_bytes)
      return nil if value.nil?
      text = text!(value, max_bytes, empty: true)
      text.empty? ? nil : text
    end
    private_class_method :optional_text!

    def self.tags!(value)
      invalid! unless value.is_a?(Array) && value.length <= 128
      value.map { |tag| text!(tag, 128) }.uniq
    end
    private_class_method :tags!

    def self.timestamp!(value)
      return nil if value.nil?
      if value.is_a?(Integer)
        invalid! unless value.between?(0, MAX_ID)
        time = Time.at(Rational(value, 1000)).utc
      else
        invalid! unless value.is_a?(String) && value.bytesize <= 64
        match = /\A(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,9})?(Z|[+-]\d{2}:?\d{2})\z/.match(value)
        invalid! unless match && Date.valid_date?(match[1].to_i, match[2].to_i, match[3].to_i) &&
          match[4].to_i < 24 && match[5].to_i < 60 && match[6].to_i < 60
        offset = match[7].delete(":")
        invalid! unless offset == "Z" || (offset[1, 2].to_i < 24 && offset[3, 2].to_i < 60)
        time = Time.iso8601(value).utc
      end
      invalid! unless time.year.between?(1000, 9999)
      time
    rescue ArgumentError, RangeError
      invalid!
    end
    private_class_method :timestamp!

    def self.invalid!
      raise Error, "Invalid MyMiniFactory JSON."
    end
    private_class_method :invalid!
  end
end
