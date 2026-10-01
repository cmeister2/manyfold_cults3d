# frozen_string_literal: true

module ManyfoldMyminifactory
  class StatusController < ::ApplicationController
    def index
      skip_policy_scope
      @linked = SiteSettings.myminifactory_api_key.present?
      import = SiteSettings.find_by(var: "manyfold_myminifactory_import_json")
      return unless import&.value.present?

      @model_count = LibraryModel.count
      @imported_at = import.updated_at
    end
  end
end
