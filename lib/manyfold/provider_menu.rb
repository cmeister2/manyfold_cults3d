# frozen_string_literal: true

# Providers bundle this helper and require it by the same path so Ruby loads
# one copy. Each provider supplies a component with a label and dropdown item.
module Manyfold
  module ProviderMenu
    def self.register(component)
      unless PluginManager.components_for(:provider_menu).include?(component)
        PluginManager.register(:provider_menu, component)
      end
      unless PluginManager.components_for(:navbar).include?(Dropdown)
        PluginManager.register(:navbar, Dropdown)
      end
    end

    class Dropdown < Components::Base
      def view_template
        items = PluginManager.components_for(:provider_menu).uniq.select do |component|
          !component.respond_to?(:visible?) || component.visible?(view_context)
        end.sort_by { |component| [component.label.downcase, component.name] }
        return if items.empty?

        div(class: "dropdown") do
          button(type: "button", id: "nav-link-providers", class: "nav-link dropdown-toggle", title: "Providers",
            data: {bs_toggle: "dropdown"}, aria: {label: "Providers", expanded: false, haspopup: "menu", controls: "providers-menu"}) do
            Icon(icon: "plug", role: "presentation")
            whitespace
            span(class: "d-md-none d-lg-inline") { "Providers" }
          end
          ul(class: "dropdown-menu", id: "providers-menu", role: "menu", aria: {labelledby: "nav-link-providers"}) do
            items.each { |component| render component.new }
          end
        end
      end
    end
  end
end
