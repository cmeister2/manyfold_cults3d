# frozen_string_literal: true

module ManyfoldCults3d
  class LinkedModels
    def self.for(entries, models:)
      entries = entries.to_a
      result = entries.to_h { |entry| [entry.cults3d_id, []] }
      return result if entries.empty?

      explicit = models.where(id: entries.filter_map(&:model_id)).index_by(&:id)
      identifiers = Hash.new { |hash, key| hash[key] = [] }
      slugs = Hash.new { |hash, key| hash[key] = [] }
      entries.each do |entry|
        model = explicit[entry.model_id]
        result.fetch(entry.cults3d_id) << model if model
        identifiers[Source.identifier_for(entry.cults3d_id)] << entry.cults3d_id
        slugs[entry.slug] << entry.cults3d_id if Source.valid_slug?(entry.slug)
      rescue Source::Invalid
        next
      end

      links = ::Link.where(linkable_type: "Model", linkable_id: models.select(:id))
        .where(::Link.arel_table[:url].matches("%cults3d.com/%"))
        .includes(:linkable)
      links.find_each do |link|
        source = Source.new(link.url)
        ids = source.identifier ? identifiers[source.identifier] : slugs[source.slug]
        ids.each { |id| result.fetch(id) << link.linkable } if link.linkable
      rescue Source::Invalid
        next
      end
      result.transform_values { |matches| matches.uniq(&:id).sort_by(&:id) }
    end
  end
end
