# frozen_string_literal: true

module ManyfoldMyminifactory
  class LinkedModels
    def self.for(entries, models:)
      entries = entries.to_a
      result = entries.to_h { |entry| [entry.myminifactory_id, []] }
      return result if entries.empty?

      explicit = models.where(id: entries.filter_map(&:model_id)).index_by(&:id)
      entries.each do |entry|
        model = explicit[entry.model_id]
        result.fetch(entry.myminifactory_id) << model if model
      end

      links = ::Link.where(linkable_type: "Model", linkable_id: models.select(:id))
        .where(::Link.arel_table[:url].matches("%myminifactory.com/object/%"))
        .includes(:linkable)
      links.find_each do |link|
        id = Source.new(link.url).id.to_i
        matches = result[id]
        matches << link.linkable if matches && link.linkable
      rescue Source::Invalid
        next
      end
      result.transform_values { |matches| matches.uniq(&:id).sort_by(&:id) }
    end
  end
end
