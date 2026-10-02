# frozen_string_literal: true

Rails.application.config.after_initialize do
  require "manyfold/provider_menu"
  Manyfold::ProviderMenu.register(Components::ManyfoldMyminifactory::ProviderMenuItem)
  PluginManager.register(:model_menu, Components::ManyfoldMyminifactory::ModelMenu)
end
