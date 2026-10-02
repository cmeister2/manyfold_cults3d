# frozen_string_literal: true

require "uri"

module ManyfoldCults3d
  class CreatorModels
    def self.linked?(creator, models:)
      links(creator, models: models).find_each(batch_size: 100).any? { |link| valid_source?(link.url) }
    end

    def self.links_for(creator, models:)
      links(creator, models: models).includes(:linkable).order(:id)
        .select { |link| valid_source?(link.url) }.uniq(&:url)
    end

    def self.source(url)
      text = url.to_s.strip
      uri = URI.parse(text)
      if uri.is_a?(URI::HTTP) && uri.scheme == "http" && uri.port == 80 &&
          !uri.userinfo && Source::HOSTS.include?(uri.host&.downcase)
        text = URI::HTTPS.build(host: uri.host, path: uri.path, query: uri.query, fragment: uri.fragment).to_s
      end
      Source.new(text)
    rescue URI::InvalidURIError, URI::InvalidComponentError, ArgumentError
      raise Source::Invalid, Source::MESSAGE, cause: nil
    end

    def self.links(creator, models:)
      ::Link.where(linkable_type: "Model", linkable_id: models.where(creator_id: creator.id).select(:id))
        .where(::Link.arel_table[:url].matches("%cults3d.com%"))
    end
    private_class_method :links

    def self.valid_source?(url)
      source(url)
      true
    rescue Source::Invalid
      false
    end
    private_class_method :valid_source?
  end
end
