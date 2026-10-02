# frozen_string_literal: true

module Components::ManyfoldCults3d
  class ProviderMenuItem < Components::Base
    def self.label
      "Cults3D"
    end

    def view_template
      DropdownItem(label: self.class.label, icon: "box-seam", path: view_context.manyfold_cults3d.root_path)
    end
  end
end
