# frozen_string_literal: true

module ManyfoldCults3d
  class ImportsController < ::ApplicationController
    before_action { authorize :settings, :integrations? }
    protect_from_forgery with: :exception

    def new
      @configured = ApiClient.configured?
    end

    def create
      models = Inventory.attributes(ApiClient.new.library)
      ids = models.map { |attributes| attributes.fetch(:cults3d_id) }
      LibraryModel.transaction do
        models.each do |attributes|
          model = LibraryModel.find_or_initialize_by(cults3d_id: attributes.fetch(:cults3d_id))
          model.update!(attributes)
        end
        # Keep Manyfold models and their files when pruning provider entries.
        LibraryModel.where.not(cults3d_id: ids).delete_all
        SiteSettings.manyfold_cults3d_imported_at = Time.current.iso8601
      end
      redirect_to manyfold_cults3d.root_path,
        notice: "#{helpers.pluralize(models.length, 'model')} imported.", status: :see_other
    rescue ApiClient::Error, Inventory::Error => error
      @configured = ApiClient.configured?
      flash.now[:alert] = error.message
      render :new, status: :unprocessable_content
    rescue ActiveRecord::RecordInvalid, ActiveRecord::StatementInvalid
      @configured = ApiClient.configured?
      flash.now[:alert] = "Could not save your Cults3D library. Your saved library has not changed."
      render :new, status: :unprocessable_content
    end
  end
end
