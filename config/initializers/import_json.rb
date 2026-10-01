# frozen_string_literal: true

Rails.application.config.to_prepare do
  unless SiteSettings.keys.include?("manyfold_myminifactory_import_json")
    SiteSettings.field :manyfold_myminifactory_import_json, type: :string
  end
end
