# frozen_string_literal: true

module ManyfoldMyminifactory
  class SyncJob < ::UpdateMetadataFromLinkJob
    def perform(model_id, user_id, object_id)
      model = ::Model.find(model_id)
      user = ::User.find(user_id)
      return unless user.is_administrator? && ::ModelPolicy.new(user, model).sync?

      id = Source.new(object_id).id
      payload = ApiClient.new.object(id)
      unless payload.is_a?(Hash) && payload["id"].to_s == id
        raise ApiClient::InvalidResponse, "MyMiniFactory returned an unexpected model."
      end
      deserializer = ObjectDeserializer.new(payload: payload)
      link = model.links.find_or_create_by!(url: deserializer.uri)
      link.define_singleton_method(:deserializer) { deserializer }
      status.update(model_id: model.id, object_id: id)
      super(link: link, organize: false)
    rescue ApiClient::Error, Source::Invalid => error
      status.update(error: "manyfold_myminifactory.errors.request_failed", mmf_message: error.message)
    rescue ActiveRecord::RecordInvalid => error
      status.update(error: "manyfold_myminifactory.errors.sync_failed", mmf_message: error.message)
    end
  end
end
