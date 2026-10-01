# frozen_string_literal: true

module ManyfoldMyminifactory
  class LinksController < ::ApplicationController
    before_action :load_model
    protect_from_forgery with: :exception

    def new
      @source = params.permit(:source)[:source].to_s
      prepare_form
    end

    def create
      @source = params.permit(:source)[:source].to_s
      source = Source.new(@source)
      if SiteSettings.myminifactory_api_key.blank?
        raise ApiClient::ConfigurationError, "Set your MyMiniFactory API key in integration settings first."
      end

      SyncJob.perform_later(@model.id, current_user.id, source.id)
      redirect_to main_app.model_path(@model), notice: "MyMiniFactory sync is queued.", status: :see_other
    rescue Source::Invalid, ApiClient::Error => error
      @error = error.message
      prepare_form
      render :new, status: :unprocessable_content
    end

    private

    def load_model
      authorize :settings, :integrations?
      @model = policy_scope(::Model).find_param(params.permit(:model_id)[:model_id])
      authorize @model, :sync?
    end

    def prepare_form
      @match_query = (params.key?(:match_q) ? params.permit(:match_q)[:match_q] : @model.name).to_s.strip.slice(0, 200)
      @library_matches = []
      items = LibraryModel.order(:myminifactory_id).limit(LibraryMatcher::MAX_ITEMS + 1)
        .pluck(:myminifactory_id, :name, :creator_name).map do |id, name, creator|
          {"id" => id, "name" => name, "creator_name" => creator.to_s}
        end
      @has_library = items.any?
      @library_matches = LibraryMatcher.new(items)
        .matches(name: @match_query, creator: @model.creator&.name, limit: 5)
    rescue LibraryMatcher::Error => error
      @match_error = error.message
    end
  end
end
