# frozen_string_literal: true

module ManyfoldMyminifactory
  class ImportsController < ::ApplicationController
    before_action { authorize :settings, :integrations? }
    protect_from_forgery with: :exception

    def new
    end

    def create
      @json = params.permit(:json)[:json].to_s
      models = Inventory.parse(@json)
      SiteSettings.transaction do
        models.each do |attributes|
          model = LibraryModel.find_or_initialize_by(myminifactory_id: attributes.fetch(:myminifactory_id))
          model.update!(attributes)
        end
        SiteSettings.manyfold_myminifactory_import_json = @json
        SiteSettings.find_by!(var: "manyfold_myminifactory_import_json").touch
      end
      redirect_to manyfold_myminifactory.import_path, notice: "JSON saved.", status: :see_other
    rescue JSON::ParserError, Inventory::Error
      flash.now[:alert] = "Invalid JSON."
      render :new, status: :unprocessable_content
    end
  end
end
