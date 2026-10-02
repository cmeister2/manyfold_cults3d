# frozen_string_literal: true

Rails.application.config.after_initialize do
  require "manyfold/provider_menu"
  Manyfold::ProviderMenu.register(Components::ManyfoldCults3d::ProviderMenuItem)
  PluginManager.register(:model_menu, Components::ManyfoldCults3d::ModelMenu)
end
