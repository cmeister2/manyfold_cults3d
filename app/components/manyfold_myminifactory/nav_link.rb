# frozen_string_literal: true

module Components::ManyfoldMyminifactory
  class NavLink < Components::Base
    def view_template
      a(href: view_context.manyfold_myminifactory.root_path, class: "nav-link", title: "MyMiniFactory", aria: {label: "MyMiniFactory"}) do
        Icon(icon: "box-seam", role: "presentation")
        plain " "
        span(class: "d-md-none d-lg-inline") { "MyMiniFactory" }
      end
    end
  end
end
