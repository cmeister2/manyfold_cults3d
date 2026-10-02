# frozen_string_literal: true

module ManyfoldCults3d
  class CreatorSyncJob < ::UpdateMetadataFromLinkJob
    def perform(creator_id, user_id, model_link_id)
      creator = ::Creator.find_by(id: creator_id)
      user = ::User.find_by(id: user_id)
      return unless creator && user&.is_administrator? && ::CreatorPolicy.new(user, creator).sync?
      return if CreatorSource.linked?(creator)

      model_link = ::Link.find_by(id: model_link_id, linkable_type: "Model")
      return unless model_link
      model = ::ModelPolicy::Scope.new(user, ::Model).resolve
        .find_by(id: model_link.linkable_id, creator_id: creator.id)
      return unless model

      source = CreatorModels.source(model_link.url)
      payload = ApiClient.new.object(source.id)
      unless source.matches?(payload)
        raise ApiClient::InvalidResponse, "Cults3D returned an unexpected model."
      end
      profile = CreatorSource.from_payload(payload["creator"])
      deserializer = CreatorDeserializer.new(uri: profile.uri, payload: payload["creator"])
      creator.with_lock do
        return if CreatorSource.linked?(creator)

        link = creator.links.find_or_create_by!(url: deserializer.uri)
        link.define_singleton_method(:deserializer) { deserializer }
        status.update(creator_id: creator.id, model_id: model.id)
        super(link: link, organize: false)
      end
    rescue ApiClient::Error, Source::Invalid, CreatorSource::Invalid => error
      status.update(error: "manyfold_cults3d.errors.creator_request_failed", cults3d_message: error.message)
    rescue ActiveRecord::RecordInvalid => error
      status.update(error: "manyfold_cults3d.errors.creator_sync_failed", cults3d_message: error.message)
    end
  end
end
