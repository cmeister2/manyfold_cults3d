# frozen_string_literal: true

class CreateManyfoldMyminifactoryLibraryModels < ActiveRecord::Migration[8.0]
  def change
    create_table :manyfold_myminifactory_library_models do |table|
      table.bigint :myminifactory_id, null: false
      table.string :name, null: false
      table.datetime :source_created_at
      table.datetime :source_updated_at
      table.datetime :published_at
      table.string :creator_name
      table.bigint :creator_id
      table.string :creator_username
      table.text :creator_avatar
      table.json :tags, null: false
      table.json :sources, null: false
      table.datetime :library_added_at
      table.json :library_entries, null: false
      table.timestamps
    end
    add_index :manyfold_myminifactory_library_models, :myminifactory_id, unique: true
  end
end
