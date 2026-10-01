# frozen_string_literal: true

module Components::ManyfoldMyminifactory
  class ModelMenu < Components::Base
    def initialize(model:)
      @model = model
    end

    def view_template
      return if SiteSettings.myminifactory_api_key.blank?
      return unless current_user && policy(:settings).integrations? && policy(@model).sync?

      a(href: view_context.manyfold_myminifactory.link_path(model_id: @model.to_param),
        class: "dropdown-item", role: "menuitem", rel: "nofollow") do
        Icon(icon: "link-45deg", label: "Link to MyMiniFactory")
        whitespace
        span { "Link to MyMiniFactory" }
      end
    end
  end
end
