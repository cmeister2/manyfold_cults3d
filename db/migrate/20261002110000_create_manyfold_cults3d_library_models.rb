# frozen_string_literal: true

class CreateManyfoldCults3dLibraryModels < ActiveRecord::Migration[8.0]
  def change
    create_table :manyfold_cults3d_library_models do |table|
      table.string :cults3d_id, null: false
      table.string :slug, null: false
      table.text :url, null: false
      table.string :name, null: false
      table.datetime :published_at
      table.string :creator_name
      table.string :creator_username
      table.text :creator_avatar
      table.json :tags, null: false
      table.json :sources, null: false
      table.datetime :library_added_at
      table.json :library_entries, null: false
      table.timestamps
    end
    add_index :manyfold_cults3d_library_models, :cults3d_id, unique: true
    add_index :manyfold_cults3d_library_models, :slug
  end
end
