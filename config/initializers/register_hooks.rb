# frozen_string_literal: true

Rails.application.config.after_initialize do
  require "manyfold/provider_menu"
  Manyfold::ProviderMenu.register(Components::ManyfoldCults3d::ProviderMenuItem)
  PluginManager.register(:model_menu, Components::ManyfoldCults3d::ModelMenu)
  PluginManager.register(:creator_menu, Components::ManyfoldCults3d::CreatorMenu)
end

Rails.application.config.to_prepare do
  require "manyfold_cults3d/creator_menu"
  require "manyfold_cults3d/creator_links"
  ManyfoldCults3d::CreatorMenu.install!
  ManyfoldCults3d::CreatorLinks.install!
end
