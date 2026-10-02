# frozen_string_literal: true

Rails.application.config.to_prepare do
  unless SiteSettings.keys.include?("manyfold_cults3d_imported_at")
    SiteSettings.field :manyfold_cults3d_imported_at, type: :string
  end
end
