# frozen_string_literal: true

module ManyfoldCults3d
  class StatusController < ::ApplicationController
    def index
      @linked = ApiClient.configured?
      @library_models = LibraryModel.order(:name, :cults3d_id).to_a
      visible_models = policy_scope(::Model)
      models = policy(:settings).integrations? ? ::Model.all : visible_models
      @linked_models = LinkedModels.for(@library_models, models: models)
      linked_ids = @linked_models.values.flatten.map(&:id).uniq
      @visible_model_ids = visible_models.where(id: linked_ids).pluck(:id).to_h { |id| [id, true] }
      import = SiteSettings.find_by(var: "manyfold_cults3d_imported_at")
      return unless import&.value.present?

      @model_count = @library_models.size
      @imported_at = import.updated_at
    end
  end
end
