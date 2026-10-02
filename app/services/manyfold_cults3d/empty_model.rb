# frozen_string_literal: true

module ManyfoldCults3d
  class EmptyModel
    class Error < StandardError; end

    def self.create!(entry:, owner:)
      entry.with_lock do
        existing = LinkedModels.for([entry], models: ::Model.all).fetch(entry.cults3d_id).first
        next existing if existing

        library = ::Library.default
        raise Error, "Set up a Manyfold library before creating a model." unless library

        model = ::Model.new(name: entry.name, library: library, path: SecureRandom.uuid,
          owner: owner, permission_preset: :private)
        # Host callbacks normally generate metadata files and download archives.
        # Keep the initial placeholder empty until its sync job runs.
        model.define_singleton_method(:write_datapackage_later) { |**| }
        model.define_singleton_method(:pregenerate_downloads) { |**| }
        model.save!
        entry.update!(model: model)
        yield model if block_given?
        model
      end
    end
  end
end
