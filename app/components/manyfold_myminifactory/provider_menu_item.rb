# frozen_string_literal: true

module Components::ManyfoldMyminifactory
  class ProviderMenuItem < Components::Base
    def self.label
      "MyMiniFactory"
    end

    def view_template
      DropdownItem(label: self.class.label, icon: "box-seam", path: view_context.manyfold_myminifactory.root_path)
    end
  end
end
