# frozen_string_literal: true

module ManyfoldCults3d
  # Older Manyfold versions have no creator menu hook. Keep their card template
  # and its existing menu items, and add the hook while that card is rendered.
  module CreatorMenu
    CONTEXT = :@manyfold_cults3d_creator_menu

    def self.install!
      ActionView::Template.prepend(TemplateContext) unless ActionView::Template < TemplateContext
      ComponentsHelper.prepend(MenuItems) unless ComponentsHelper < MenuItems
    end

    module TemplateContext
      def render(view, locals, *arguments, **options, &block)
        previous = view.instance_variable_get(CONTEXT)
        creator = if virtual_path == "creators/_creator" &&
            !source.match?(/components_for\s*(?:\(\s*)?:creator_menu\b/)
          locals[:creator]
        end
        view.instance_variable_set(CONTEXT, creator)
        super
      ensure
        view.instance_variable_set(CONTEXT, previous)
      end
    end

    module MenuItems
      def BurgerMenu(**arguments, &block)
        creator = instance_variable_get(CONTEXT)
        components = PluginManager.components_for(:creator_menu)
        return super unless creator && block && components.any?

        super(**arguments) do |*block_arguments|
          original_items = capture(*block_arguments, &block)
          additional_items = components.filter_map do |component|
            content = render(component.new(creator: creator))
            content_tag(:li, content, role: "presentation") if content.present?
          end
          safe_join([original_items, *additional_items])
        end
      end
    end
  end
end
