# frozen_string_literal: true

class AddModelToManyfoldMyminifactoryLibraryModels < ActiveRecord::Migration[8.0]
  def change
    add_reference :manyfold_myminifactory_library_models, :model,
      foreign_key: {to_table: :models, on_delete: :nullify}
  end
end
