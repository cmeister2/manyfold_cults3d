# frozen_string_literal: true

module ManyfoldMyminifactory
  class ImportsController < ::ApplicationController
    before_action { authorize :settings, :integrations? }
    protect_from_forgery with: :exception

    def new
      @json = SiteSettings.manyfold_myminifactory_import_json
    end

    def create
      @json = params.permit(:json)[:json].to_s
      JSON.parse(@json)
      SiteSettings.manyfold_myminifactory_import_json = @json
      redirect_to manyfold_myminifactory.import_path, notice: "JSON saved.", status: :see_other
    rescue JSON::ParserError
      flash.now[:alert] = "Invalid JSON."
      render :new, status: :unprocessable_content
    end
  end
end
