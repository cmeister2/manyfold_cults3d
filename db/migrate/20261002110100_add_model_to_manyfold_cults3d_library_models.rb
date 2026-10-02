# frozen_string_literal: true

class AddModelToManyfoldCults3dLibraryModels < ActiveRecord::Migration[8.0]
  def change
    add_reference :manyfold_cults3d_library_models, :model,
      foreign_key: {to_table: :models, on_delete: :nullify}
  end
end
