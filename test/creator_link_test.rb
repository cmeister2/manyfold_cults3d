# frozen_string_literal: true

require "uri"
require "cgi"

# Fictional local creators and model links only; no external API requests.
class Cults3DPluginTest
  class FakeCreatorLinkClient
    attr_reader :object_calls, :creator_calls
    attr_accessor :profile

    def initialize(payload)
      @payload = payload
      @profile = payload.is_a?(Hash) ? payload["creator"] : nil
      @object_calls = []
      @creator_calls = []
    end

    def object(id)
      @object_calls << id.to_s
      raise @payload if @payload.is_a?(Exception)
      Marshal.load(Marshal.dump(@payload))
    end

    def creator(username)
      @creator_calls << username
      raise @profile if @profile.is_a?(Exception)
      Marshal.load(Marshal.dump(@profile))
    end
  end

  def test_creator_card_menu_preserves_native_actions_and_mount_prefixes
    configure_api
    with_creator_model do |creator, model, source_link|
      assert_includes PluginManager.components_for(:creator_menu), Components::ManyfoldCults3d::CreatorMenu
      2.times { ManyfoldCults3d::CreatorMenu.install! }
      ["", "/manyfold"].each do |prefix|
        session = browser(@users.first)
        document = creator_index_document(session, prefix)
        card = creator_card(document, creator)
        native_items = card.css('a[href]')
        assert native_items.any? { |item| item["href"] == "#{prefix}/creators/#{creator.to_param}/edit" }
        assert native_items.any? { |item| item["href"] == "#{prefix}/creators/#{creator.to_param}" && (item["data-method"] || item["data-turbo-method"]) == "delete" }
        menu_items = creator_link_menu_items(card)
        assert_equal 1, menu_items.size
        item = menu_items.first
        assert_equal "menuitem", item["role"]
        assert_equal "li", item.parent.name
        assert_equal "presentation", item.parent["role"]
        assert_equal "ul", item.parent.parent.name
        refute_nil item.at_css('i.bi.bi-link-45deg')
        uri = URI.parse(item["href"])
        assert_equal "#{prefix}/manyfold_cults3d/creator_link", uri.path
        assert_equal creator.to_param, CGI.parse(uri.query).fetch("creator_id").first

        client = FakeCreatorLinkClient.new(fake_creator_link_payload)
        with_api_client(client) do
          session.get(item["href"].delete_prefix(prefix), env: {"SCRIPT_NAME" => prefix})
        end
        assert_equal 200, session.response.status
        form = creator_link_form_document(session)
        assert_equal "#{prefix}/manyfold_cults3d/creator_link", form["action"]
        assert_equal [source_link.id.to_s], form.css('input[type="radio"][name="link_id"]').map { |radio| radio["value"] }
        assert_includes form.text, model.name
        assert_empty client.object_calls
        assert_empty client.creator_calls
        assert_empty creator_link_jobs
        assert_empty creator.links.reload
      end
    end
  end

  def test_creator_menu_requires_both_credentials_and_an_eligible_model_link
    configure_api
    with_creator_model do |creator, model, source_link|
      session = browser(@users.first)
      [[nil, "fictional-api-key"], ["fictional-user", nil], ["fictional-user", " "],
        ["fictional-user", "fictional-api-key"]].each do |username, key|
        configure_api(key, username)
        card = creator_card(creator_index_document(session), creator)
        expected = username.present? && key.present? ? 1 : 0
        assert_equal expected, creator_link_menu_items(card).size
      end

      source_link.destroy!
      assert_empty creator_link_menu_items(creator_card(creator_index_document(session), creator))
      ["https://example.invalid/en/3d-model/art/fictional-model-92001",
        "https://cults3d.com.example.invalid/en/3d-model/art/fictional-model-92001",
        "https://user@cults3d.com/en/3d-model/art/fictional-model-92001",
        "http://cults3d.com:8080/en/3d-model/art/fictional-model-92001",
        "https://cults3d.com/en/users/example-profile-sync-studio"].each do |url|
        link = model.links.create!(url: url)
        assert_empty creator_link_menu_items(creator_card(creator_index_document(session), creator)), url
        link.destroy!
      end
      assert_empty creator.links.reload
      assert_empty creator_link_jobs
    end
  end

  def test_creator_menu_hides_when_any_cults3d_profile_is_already_linked
    configure_api
    with_creator_model do |creator, _model, _source_link|
      session = browser(@users.first)
      ["https://cults3d.com/en/users/example-profile-sync-studio",
        "http://www.cults3d.com/fr/utilisateurs/example-profile-sync-studio/fichiers-3d?ref=example",
        "https://www.cults3d.com/de/benutzer/example-profile-sync-studio/3d-modelle/"].each do |url|
        profile_link = creator.links.create!(url: url)
        card = creator_card(creator_index_document(session), creator)
        assert_empty creator_link_menu_items(card), url
        profile_link.destroy!
      end

      unrelated_link = creator.links.create!(url: "https://cults3d.com.example.invalid/en/users/example-profile-sync-studio")
      assert_equal 1, creator_link_menu_items(creator_card(creator_index_document(session), creator)).size
      unrelated_link.destroy!
    end
  end

  def test_creator_link_uses_existing_http_model_links_without_rewriting_them
    configure_api
    ["http://www.cults3d.com/en/3d-model/art/fictional-model-92001?ref=example",
      "http://cults3d.com:80/en/3d-model/art/fictional-model-92001",
      "https://www.cults3d.com:443/en/3d-model/art/fictional-model-92001"].each do |original_url|
      with_creator_model do |creator, model, source_link|
        source_link.update!(url: original_url)
        model_before = creator_model_snapshot(model)
        session = browser(@users.first)
        card = creator_card(creator_index_document(session), creator)
        assert_equal 1, creator_link_menu_items(card).size, original_url
        form = get_creator_link_form(session, creator)
        assert_equal [source_link.id.to_s], form.css('input[name="link_id"]').map { |radio| radio["value"] }
        post_creator_link(session, creator, source_link.id, form)
        assert_equal 303, session.response.status
        assert_equal [creator.id, @users.first.id, source_link.id], creator_link_jobs.last[:args]

        payload = fake_creator_link_payload
        payload["creator"]["imageUrl"] = nil
        client = FakeCreatorLinkClient.new(payload)
        with_api_client(client) { ActiveJob::Base.deserialize(creator_link_jobs.last).perform_now }
        assert_equal ["fictional-model-92001"], client.object_calls
        assert_equal "Fictional synchronized creator biography.", creator.reload.notes
        assert_equal ["https://cults3d.com/en/users/example-profile-sync-studio"], creator.links.pluck(:url)
        refute_nil creator.links.first.synced_at
        assert_equal original_url, source_link.reload.url
        assert_equal model_before, creator_model_snapshot(model)
      end
    end
  end

  def test_creator_menu_respects_administrator_local_creator_and_model_visibility
    configure_api
    with_creator_model do |creator, model, source_link|
      session = browser(@users.last)
      assert_empty creator_link_menu_items(creator_card(creator_index_document(session), creator))

      session = browser(@users.first)
      model.update!(sensitive: true)
      @users.first.update!(sensitive_content_handling: "hide")
      assert_empty creator_link_menu_items(creator_card(creator_index_document(session), creator))
      form = get_creator_link_form(session, creator)
      assert_empty form.css('input[name="link_id"]')
      assert form.at_css('input[type="submit"], button[type="submit"]')["disabled"]
      refute_includes session.response.body, model.name
      post_creator_link(session, creator, source_link.id, form)
      assert_equal 422, session.response.status
      assert_empty creator_link_jobs

      model.update!(sensitive: false)
      creator.federails_actor.update_columns(local: false)
      refute ::CreatorPolicy.new(@users.first, creator.reload).sync?
      assert_empty creator_link_menu_items(creator_card(creator_index_document(session), creator))
      session.get("/manyfold_cults3d/creator_link", params: {creator_id: creator.to_param})
      assert_equal 404, session.response.status
    end
  end

  def test_creator_link_queues_only_the_selected_associated_model_link
    configure_api
    with_creator_model do |creator, model, first_link|
      second_link = model.links.create!(url: "https://cults3d.com/en/3d-model/art/fictional-model-92002")
      ["", "/manyfold"].each do |prefix|
        session = browser(@users.first)
        form = get_creator_link_form(session, creator, prefix)
        assert_equal [first_link.id.to_s, second_link.id.to_s].sort,
          form.css('input[name="link_id"]').map { |radio| radio["value"] }.sort
        original = creator.attributes
        model_before = creator_model_snapshot(model)
        jobs_before = creator_link_jobs.size
        selected_link = prefix.empty? ? first_link : second_link
        post_creator_link(session, creator, selected_link.id, form, prefix)
        assert_equal 303, session.response.status
        assert_equal "#{session.request.base_url}#{prefix}/creators", session.response.location
        assert_equal "Cults3D creator sync is queued.", session.request.flash[:notice]
        assert_equal jobs_before + 1, creator_link_jobs.size
        assert_equal [creator.id, @users.first.id, selected_link.id], creator_link_jobs.last[:args]
        assert_equal original, creator.reload.attributes
        assert_equal model_before, creator_model_snapshot(model)
        assert_empty creator.links.reload
      end
    end
  end

  def test_creator_link_rejects_missing_invalid_and_unrelated_selection_without_mutations
    configure_api
    with_creator_model do |creator, model, _source_link|
      with_native_model(name: "Unrelated fictional creator model") do |other_model|
        other_creator = ::Creator.create!(name: "Other fictional creator #{SecureRandom.hex(6)}",
          permission_preset: "member", owner: @users.first)
        other_model.update!(creator: other_creator)
        unrelated = other_model.links.create!(url: "https://cults3d.com/en/3d-model/art/fictional-model-92002")
        invalid = model.links.create!(url: "https://example.invalid/en/3d-model/art/fictional-model-92001")
        session = browser(@users.first)
        original = creator.attributes
        model_before = creator_model_snapshot(model)
        [nil, "", "0", "invalid", unrelated.id, invalid.id, [unrelated.id]].each do |selection|
          form = get_creator_link_form(session, creator)
          post_creator_link(session, creator, selection, form)
          assert_equal 422, session.response.status, selection.inspect
          assert_empty creator_link_jobs
          assert_empty creator.links.reload
          assert_equal original, creator.reload.attributes
          assert_equal model_before, creator_model_snapshot(model)
        end
      end
    end
  end

  def test_creator_link_requires_csrf_and_credentials_before_queueing
    configure_api
    with_creator_model do |creator, _model, source_link|
      session = browser(@users.first)
      get_creator_link_form(session, creator)
      session.post("/manyfold_cults3d/creator_link", params: {creator_id: creator.to_param, link_id: source_link.id},
        headers: {"HTTP_ORIGIN" => session.request.base_url})
      assert_equal 422, session.response.status
      assert_empty creator_link_jobs

      [[nil, "fictional-api-key"], ["fictional-user", nil]].each do |username, key|
        configure_api(key, username)
        form = get_creator_link_form(session, creator)
        assert form.at_css('input[type="submit"], button[type="submit"]')["disabled"]
        post_creator_link(session, creator, source_link.id, form)
        assert_equal 422, session.response.status
        assert_empty creator_link_jobs
        assert_empty creator.links.reload
      end
    end
  end

  def test_creator_link_requires_admin_existing_creator_and_sync_permission
    configure_api
    with_creator_model do |creator, _model, source_link|
      session = browser(@users.last)
      document = creator_index_document(session)
      token = document.at_css('meta[name="csrf-token"]')["content"]
      assert_creator_link_forbidden(session, creator.to_param, source_link.id, token)
      session = browser(@users.first)
      form = get_creator_link_form(session, creator)
      token = form.at_css('input[name="authenticity_token"]')["value"]
      assert_creator_link_forbidden(session, "missing-fictional-creator", source_link.id, token)
      creator.federails_actor.update_columns(local: false)
      assert_creator_link_forbidden(session, creator.to_param, source_link.id, token)
      assert_empty creator.links.reload
      assert_empty creator_link_jobs
    end
  end

  def test_creator_link_with_no_candidates_shows_a_disabled_form_and_does_not_queue
    configure_api
    with_creator_model do |creator, _model, source_link|
      removed_id = source_link.id
      source_link.destroy!
      session = browser(@users.first)
      form = get_creator_link_form(session, creator)
      assert_empty form.css('input[name="link_id"]')
      assert form.at_css('input[type="submit"], button[type="submit"]')["disabled"]
      assert_match(/no .*Cults3D/i, session.response.body)
      post_creator_link(session, creator, removed_id, form)
      assert_equal 422, session.response.status
      assert_empty creator_link_jobs
      assert_empty creator.links.reload
    end
  end

  def test_creator_link_post_is_idempotent_when_a_profile_link_was_added_after_get
    configure_api
    with_creator_model do |creator, _model, source_link|
      session = browser(@users.first)
      form = get_creator_link_form(session, creator)
      profile_link = creator.links.create!(url: "http://www.cults3d.com/fr/users/example-profile-sync-studio/3d-models")
      2.times do
        post_creator_link(session, creator, source_link.id, form)
        assert_equal 303, session.response.status
        assert_equal "#{session.request.base_url}/creators", session.response.location
        assert_equal "Creator is already linked to Cults3D.", session.request.flash[:notice]
        assert_empty creator_link_jobs
        assert_equal [profile_link.id], creator.links.reload.pluck(:id)
      end
    end
  end

  def test_creator_sync_adds_profile_and_updates_metadata_and_avatar_without_changing_models
    configure_api
    with_creator_model do |creator, model, source_link|
      filename = "creator-sync-kept.txt"
      contents = "Fictional local model file survives creator sync.\n"
      File.binwrite(File.join(@library_path, model.path, filename), contents)
      local_file = model.model_files.create!(filename: filename)
      refute_nil local_file.attachment
      model_before = creator_model_snapshot(model)
      creator_ids = ::Creator.order(:id).pluck(:id)
      model_ids = ::Model.order(:id).pluck(:id)
      owners = creator.owners.pluck(:id)
      payload = fake_creator_link_payload
      payload["creator"]["url"] = "https://www.cults3d.com/fr/users/example-profile-sync-studio/3d-models?ref=example"
      client = FakeCreatorLinkClient.new(payload)
      downloads = []
      with_status_image_download(downloads) do
        with_api_client(client) do
          2.times { ManyfoldCults3d::CreatorSyncJob.perform_now(creator.id, @users.first.id, source_link.id) }
        end
      end
      creator.reload
      assert_equal ["fictional-model-92001"], client.object_calls
      assert_empty client.creator_calls
      assert_equal "example-profile-sync-studio", creator.name
      assert_equal "example-profile-sync-studio", creator.slug
      assert_equal "Fictional synchronized creator biography.", creator.notes
      refute_nil creator.avatar
      assert creator.avatar.exists?
      assert_equal ["https://example.invalid/fictional-profile.png"], downloads
      assert_equal ["https://cults3d.com/en/users/example-profile-sync-studio"], creator.links.pluck(:url)
      refute_nil creator.links.first.synced_at
      assert_equal owners, creator.owners.pluck(:id)
      assert_equal creator_ids, ::Creator.order(:id).pluck(:id)
      assert_equal model_ids, ::Model.order(:id).pluck(:id)
      assert_equal model_before, creator_model_snapshot(model)
      assert local_file.reload.attachment.exists?
      assert_equal contents, File.binread(File.join(@library_path, model.path, filename))
    end
  end

  def test_creator_sync_rejects_api_errors_and_unexpected_model_or_profile_before_mutations
    configure_api
    with_creator_model do |creator, model, source_link|
      original = creator.attributes
      model_before = creator_model_snapshot(model)
      valid = fake_creator_link_payload
      responses = [ManyfoldCults3d::ApiClient::InvalidResponse.new("Fictional API failure."),
        valid.merge("slug" => "different-fictional-model"), valid.merge("creator" => nil),
        valid.merge("creator" => valid["creator"].merge("url" => "https://example.invalid/en/users/example-profile-sync-studio")),
        valid.merge("creator" => valid["creator"].merge("nick" => "different-fictional-creator"))]
      responses.each do |response|
        client = FakeCreatorLinkClient.new(response)
        with_api_client(client) { ManyfoldCults3d::CreatorSyncJob.perform_now(creator.id, @users.first.id, source_link.id) }
        assert_equal ["fictional-model-92001"], client.object_calls
        assert_empty creator.links.reload
        assert_nil creator.avatar
        assert_equal original, creator.reload.attributes
        assert_equal model_before, creator_model_snapshot(model)
      end
    end
  end

  def test_creator_sync_rechecks_permissions_and_model_visibility_before_api_calls
    configure_api
    with_creator_model do |creator, model, source_link|
      client = FakeCreatorLinkClient.new(fake_creator_link_payload)
      original = creator.attributes
      with_api_client(client) do
        ManyfoldCults3d::CreatorSyncJob.perform_now(creator.id, @users.last.id, source_link.id)
        @users.first.roles.delete(::Role.find_by!(name: "administrator"))
        ManyfoldCults3d::CreatorSyncJob.perform_now(creator.id, @users.first.id, source_link.id)
        @users.first.add_role(:administrator)
        model.update!(sensitive: true)
        @users.first.update!(sensitive_content_handling: "hide")
        ManyfoldCults3d::CreatorSyncJob.perform_now(creator.id, @users.first.id, source_link.id)
        model.update!(sensitive: false)
        creator.federails_actor.update_columns(local: false)
        ManyfoldCults3d::CreatorSyncJob.perform_now(creator.id, @users.first.id, source_link.id)
      end
      assert_empty client.object_calls
      assert_empty creator.links.reload
      assert_equal original, creator.reload.attributes
    end
  end

  def test_creator_sync_rolls_back_the_profile_link_when_creator_metadata_is_invalid
    configure_api
    with_creator_model do |creator, model, source_link|
      payload = fake_creator_link_payload
      payload["creator"]["imageUrl"] = nil
      ::Creator.create!(name: payload["creator"]["nick"], permission_preset: "member", owner: @users.first)
      original = creator.attributes
      model_before = creator_model_snapshot(model)
      client = FakeCreatorLinkClient.new(payload)
      with_api_client(client) { ManyfoldCults3d::CreatorSyncJob.perform_now(creator.id, @users.first.id, source_link.id) }
      assert_equal ["fictional-model-92001"], client.object_calls
      assert_empty creator.links.reload
      assert_equal original, creator.reload.attributes
      assert_equal model_before, creator_model_snapshot(model)
    end
  end

  def test_creator_sync_skips_an_existing_profile_even_when_queued_earlier
    configure_api
    with_creator_model do |creator, model, source_link|
      profile_link = creator.links.create!(url: "http://www.cults3d.com/fr/users/example-profile-sync-studio/3d-models")
      original = creator.attributes
      model_before = creator_model_snapshot(model)
      client = FakeCreatorLinkClient.new(fake_creator_link_payload)
      with_api_client(client) { ManyfoldCults3d::CreatorSyncJob.perform_now(creator.id, @users.first.id, source_link.id) }
      assert_empty client.object_calls
      assert_equal [profile_link.id], creator.links.reload.pluck(:id)
      assert_nil profile_link.reload.synced_at
      assert_equal original, creator.reload.attributes
      assert_equal model_before, creator_model_snapshot(model)
    end
  end

  def test_creator_sync_rechecks_reassigned_removed_and_invalid_source_links
    configure_api
    with_creator_model do |creator, model, source_link|
      client = FakeCreatorLinkClient.new(fake_creator_link_payload)
      original = creator.attributes
      with_api_client(client) do
        model.update!(creator: nil)
        ManyfoldCults3d::CreatorSyncJob.perform_now(creator.id, @users.first.id, source_link.id)
        model.update!(creator: creator)
        source_link.update!(url: "https://cults3d.com.example.invalid/en/3d-model/art/fictional-model-92001")
        ManyfoldCults3d::CreatorSyncJob.perform_now(creator.id, @users.first.id, source_link.id)
        source_link.destroy!
        ManyfoldCults3d::CreatorSyncJob.perform_now(creator.id, @users.first.id, source_link.id)
      end
      assert_empty client.object_calls
      assert_empty creator.links.reload
      assert_equal original, creator.reload.attributes
    end
  end

  def test_existing_creator_profile_link_supports_native_manyfold_resync
    configure_api
    with_creator_model do |creator, model, source_link|
      payload = fake_creator_link_payload
      payload["creator"]["imageUrl"] = nil
      client = FakeCreatorLinkClient.new(payload)
      with_api_client(client) { ManyfoldCults3d::CreatorSyncJob.perform_now(creator.id, @users.first.id, source_link.id) }
      profile_link = creator.links.reload.first
      refute_nil profile_link
      assert_instance_of ManyfoldCults3d::CreatorDeserializer, profile_link.deserializer
      model_before = creator_model_snapshot(model)
      first_sync = profile_link.synced_at
      client.profile = payload["creator"].merge("bio" => "Updated fictional creator biography.")
      travel_to(first_sync + 60) do
        with_api_client(client) { ::UpdateMetadataFromLinkJob.perform_now(link: profile_link, organize: false) }
      end
      assert_equal ["example-profile-sync-studio"], client.creator_calls
      assert_equal "Updated fictional creator biography.", creator.reload.notes
      assert_operator profile_link.reload.synced_at, :>, first_sync
      assert_equal [profile_link.id], creator.links.reload.pluck(:id)
      assert_equal model_before, creator_model_snapshot(model)
    end
  end

  private

  def with_creator_model
    with_native_model(name: "Fictional original model") do |model|
      creator = ::Creator.create!(name: "Fictional creator #{SecureRandom.hex(6)}", notes: "Original fictional biography.",
        permission_preset: "member", owner: @users.first)
      model.update!(creator: creator)
      source_link = model.links.create!(url: "https://cults3d.com/en/3d-model/art/fictional-model-92001")
      yield creator, model, source_link
    ensure
      creator&.federails_actor&.update_columns(local: true) if creator&.persisted?
    end
  end

  def creator_index_document(session, prefix = "")
    session.get("/creators", env: {"SCRIPT_NAME" => prefix})
    assert_equal 200, session.response.status
    Nokogiri::HTML(session.response.body)
  end

  def creator_card(document, creator)
    card = document.css('.creator-card').find { |candidate| candidate.at_css('.card-title')&.text&.include?(creator.name) }
    refute_nil card, "Creator #{creator.name} is missing from the native creators page."
    card
  end

  def creator_link_menu_items(card)
    card.css('a[href]').select { |item| item.text.strip == "Link to Cults3D" }
  end

  def get_creator_link_form(session, creator, prefix = "")
    session.get("/manyfold_cults3d/creator_link", params: {creator_id: creator.to_param}, env: {"SCRIPT_NAME" => prefix})
    assert_equal 200, session.response.status
    creator_link_form_document(session)
  end

  def creator_link_form_document(session)
    form = Nokogiri::HTML(session.response.body).at_css('#cults3d-creator-link-form')
    refute_nil form
    assert_equal "post", form["method"].downcase
    form
  end

  def post_creator_link(session, creator, link_id, form, prefix = "")
    token = form.at_css('input[name="authenticity_token"]')["value"]
    session.post("/manyfold_cults3d/creator_link", params: {creator_id: creator.to_param, link_id: link_id, authenticity_token: token},
      env: {"SCRIPT_NAME" => prefix}, headers: {"HTTP_ORIGIN" => session.request.base_url})
  end

  def assert_creator_link_forbidden(session, creator_id, link_id, token)
    session.get("/manyfold_cults3d/creator_link", params: {creator_id: creator_id})
    assert_equal 404, session.response.status
    session.post("/manyfold_cults3d/creator_link", params: {creator_id: creator_id, link_id: link_id, authenticity_token: token},
      headers: {"HTTP_ORIGIN" => session.request.base_url})
    assert_equal 404, session.response.status
  end

  def creator_link_jobs
    ActiveJob::Base.queue_adapter.enqueued_jobs.select { |job| job[:job] == ManyfoldCults3d::CreatorSyncJob }
  end

  def creator_model_snapshot(model)
    model.reload
    [model.attributes, model.links.order(:id).map(&:attributes), model.model_files.order(:id).map(&:attributes),
      model.owners.order(:id).pluck(:id)]
  end

  def fake_creator_link_payload
    fake_link_payload.merge("creator" => {"nick" => "example-profile-sync-studio",
      "bio" => "Fictional synchronized creator biography.",
      "url" => "https://cults3d.com/en/users/example-profile-sync-studio",
      "imageUrl" => "https://example.invalid/fictional-profile.png"})
  end
end
