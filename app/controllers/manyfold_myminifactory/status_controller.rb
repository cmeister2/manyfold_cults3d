# frozen_string_literal: true

module ManyfoldMyminifactory
  class StatusController < ::ApplicationController
    def index
      @linked = SiteSettings.myminifactory_api_key.present?
      @library_models = LibraryModel.order(:name, :myminifactory_id).to_a
      visible_models = policy_scope(::Model)
      models = policy(:settings).integrations? ? ::Model.all : visible_models
      @linked_models = LinkedModels.for(@library_models, models: models)
      linked_ids = @linked_models.values.flatten.map(&:id).uniq
      @visible_model_ids = visible_models.where(id: linked_ids).pluck(:id).to_h { |id| [id, true] }
      import = SiteSettings.find_by(var: "manyfold_myminifactory_import_json")
      return unless import&.value.present?

      @model_count = @library_models.size
      @imported_at = import.updated_at
    end
  end
end
