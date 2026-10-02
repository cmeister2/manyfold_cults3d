# frozen_string_literal: true

module ManyfoldCults3d
  class SyncJob < ::UpdateMetadataFromLinkJob
    def perform(model_id, user_id, object_id)
      model = ::Model.find(model_id)
      user = ::User.find(user_id)
      return unless user.is_administrator? && ::ModelPolicy.new(user, model).sync?

      source = Source.new(object_id)
      payload = ApiClient.new.object(source.id)
      unless source.matches?(payload)
        raise ApiClient::InvalidResponse, "Cults3D returned an unexpected model."
      end
      deserializer = ObjectDeserializer.new(payload: payload)
      link = model.links.find_or_create_by!(url: deserializer.uri)
      link.define_singleton_method(:deserializer) { deserializer }
      status.update(model_id: model.id, object_id: payload.fetch("identifier"))
      super(link: link, organize: false)
    rescue ApiClient::Error, Source::Invalid => error
      status.update(error: "manyfold_cults3d.errors.request_failed", cults3d_message: error.message)
    rescue ActiveRecord::RecordInvalid => error
      status.update(error: "manyfold_cults3d.errors.sync_failed", cults3d_message: error.message)
    end
  end
end
