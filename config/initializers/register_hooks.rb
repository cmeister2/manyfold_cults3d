# frozen_string_literal: true

Rails.application.config.after_initialize do
  PluginManager.register(:navbar, Components::ManyfoldMyminifactory::NavLink)
end
