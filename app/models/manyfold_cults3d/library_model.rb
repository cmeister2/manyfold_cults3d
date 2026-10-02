# frozen_string_literal: true

module ManyfoldCults3d
  class LibraryModel < ::ApplicationRecord
    self.table_name = "manyfold_cults3d_library_models"

    belongs_to :model, class_name: "::Model", optional: true
  end
end
