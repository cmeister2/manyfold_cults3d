# frozen_string_literal: true

module Components::ManyfoldCults3d
  class ModelMenu < Components::Base
    def initialize(model:)
      @model = model
    end

    def view_template
      return unless ::ManyfoldCults3d::ApiClient.configured?
      return unless current_user && policy(:settings).integrations? && policy(@model).sync?

      a(href: view_context.manyfold_cults3d.link_path(model_id: @model.to_param),
        class: "dropdown-item", role: "menuitem", rel: "nofollow") do
        Icon(icon: "link-45deg", label: "Link to Cults3D")
        whitespace
        span { "Link to Cults3D" }
      end
    end
  end
end
