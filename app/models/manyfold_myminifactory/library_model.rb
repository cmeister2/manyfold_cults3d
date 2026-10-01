# frozen_string_literal: true

module ManyfoldMyminifactory
  class LibraryModel < ::ApplicationRecord
    self.table_name = "manyfold_myminifactory_library_models"

    belongs_to :model, class_name: "::Model", optional: true
  end
end
