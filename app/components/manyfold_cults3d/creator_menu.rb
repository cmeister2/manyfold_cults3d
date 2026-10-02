# frozen_string_literal: true

module Components::ManyfoldCults3d
  class CreatorMenu < Components::Base
    register_value_helper :policy_scope

    def initialize(creator:)
      @creator = creator
    end

    def view_template
      return unless ::ManyfoldCults3d::ApiClient.configured?
      return unless current_user && policy(:settings).integrations? && policy(@creator).sync?
      return if ::ManyfoldCults3d::CreatorSource.linked?(@creator)
      return unless ::ManyfoldCults3d::CreatorModels.linked?(@creator, models: policy_scope(::Model))

      a(href: view_context.manyfold_cults3d.creator_link_path(creator_id: @creator.to_param),
        class: "dropdown-item", role: "menuitem", rel: "nofollow") do
        Icon(icon: "link-45deg", label: "Link to Cults3D")
        whitespace
        span { "Link to Cults3D" }
      end
    end
  end
end
