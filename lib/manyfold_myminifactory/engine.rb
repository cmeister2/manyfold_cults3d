# frozen_string_literal: true

module ManyfoldMyminifactory
  class Engine < ::Rails::Engine
    engine_name "manyfold_myminifactory"

    initializer "manyfold_myminifactory.append_migrations", before: "active_record.initialize_database" do |app|
      next if app.root == root

      paths["db/migrate"].expanded.each do |path|
        app.config.paths["db/migrate"] << path
      end
      # Some database tasks boot Rails without invoking db:load_config.
      ActiveSupport.on_load(:active_record) do
        ActiveRecord::Migrator.migrations_paths = app.config.paths["db/migrate"].to_a
      end
    end
  end
end
