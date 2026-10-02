# frozen_string_literal: true

module ManyfoldCults3d
  class LibraryModelsController < ::ApplicationController
    protect_from_forgery with: :exception

    def create_model
      authorize :settings, :integrations?
      authorize :model, :create?
      entry = LibraryModel.find(params.permit(:id)[:id])
      unless ApiClient.configured?
        raise ApiClient::ConfigurationError, "Set your Cults3D username and API key in integration settings first."
      end

      notice = "Model linked."
      EmptyModel.create!(entry: entry, owner: current_user) do |model|
        model_id = model.id
        user_id = current_user.id
        object_id = entry.cults3d_id.to_s
        ActiveRecord.after_all_transactions_commit do
          SyncJob.perform_later(model_id, user_id, object_id)
        end
        notice = "Model created. Cults3D sync is queued."
      end
      redirect_to manyfold_cults3d.root_path, notice: notice, status: :see_other
    rescue EmptyModel::Error, ApiClient::ConfigurationError, ActiveRecord::RecordInvalid => error
      redirect_to manyfold_cults3d.root_path, alert: error.message, status: :see_other
    end
  end
end
