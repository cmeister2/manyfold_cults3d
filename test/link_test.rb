# frozen_string_literal: true

require "uri"
require "cgi"

# Fictional names, identifiers and creator metadata only.
class Cults3DPluginTest
  class FakeLinkClient
    attr_reader :calls

    def initialize(payload)
      @payload = payload
      @calls = []
    end

    def object(id)
      @calls << id.to_s
      Marshal.load(Marshal.dump(@payload))
    end
  end

  def test_link_menu_fuzzy_search_and_selection_work_with_mount_prefixes
    configure_api("fictional-link-api-key")
    save_link_examples
    assert_includes PluginManager.components_for(:model_menu), Components::ManyfoldCults3d::ModelMenu
    ["", "/manyfold"].each do |prefix|
      with_native_model(name: "Coppre Drgaon_supported.stl") do |model|
        session = browser(@users.first)
        environment = {"SCRIPT_NAME" => prefix}
        session.get("/models/#{model.to_param}", env: environment)
        assert_equal 200, session.response.status
        document = Nokogiri::HTML(session.response.body)
        menu_link = document.css('a[href]').find { |link| link.text.strip == "Link to Cults3D" }
        refute_nil menu_link
        refute_nil menu_link.at_css('i.bi.bi-link-45deg')
        assert_equal "menuitem", menu_link["role"]
        assert_equal "li", menu_link.parent.name
        assert_equal "presentation", menu_link.parent["role"]
        assert_equal "ul", menu_link.parent.parent.name
        uri = URI.parse(menu_link["href"])
        assert_equal "#{prefix}/manyfold_cults3d/link", uri.path
        assert_equal model.to_param, CGI.parse(uri.query).fetch("model_id").first
        session.get(menu_link["href"].delete_prefix(prefix), env: environment)
        assert_equal 200, session.response.status
        document = Nokogiri::HTML(session.response.body)
        assert_equal model.name, document.at_css('input[name="match_q"]')["value"]
        search = document.at_css('#cults3d-match-form')
        assert_equal "get", search["method"].downcase
        assert_equal "#{prefix}/manyfold_cults3d/link", search["action"]
        selections = document.css('a[href]').select { |link| link.text.strip == "Use this model" }
        refute_empty selections
        selected = selections.find { |link| CGI.parse(URI.parse(link["href"]).query).fetch("source").first == creation_identifier(92001) }
        refute_nil selected
        assert_equal "cults3d-link-form", URI.parse(selected["href"]).fragment
        assert_equal model.to_param, CGI.parse(URI.parse(selected["href"]).query).fetch("model_id").first
        assert_equal model.name, CGI.parse(URI.parse(selected["href"]).query).fetch("match_q").first
        session.get(selected["href"].delete_prefix(prefix).split("#").first, env: environment)
        assert_equal 200, session.response.status
        form = link_form_document(session)
        assert_equal creation_identifier(92001), form.at_css('input[name="source"]')["value"]
        assert_equal "#{prefix}/manyfold_cults3d/link", form["action"]

        session.get("/manyfold_cults3d/link", params: {model_id: model.to_param, match_q: "Clockwrok Badger"}, env: environment)
        assert_equal 200, session.response.status
        document = Nokogiri::HTML(session.response.body)
        assert_equal "Clockwrok Badger", document.at_css('input[name="match_q"]')["value"]
        selections = document.css('a[href]').select { |link| link.text.strip == "Use this model" }
        assert_equal [creation_identifier(92002)], selections.map { |link| CGI.parse(URI.parse(link["href"]).query).fetch("source").first }
        assert_empty link_jobs
        assert_empty model.links.reload
      end
    end
  end

  def test_link_menu_requires_both_credentials_and_updates_when_removed
    with_native_model do |model|
      session = browser(@users.first)
      [[nil, "fictional-link-api-key"], ["fictional-user", nil], ["fictional-user", ""],
        ["fictional-user", "   "], ["fictional-user", "fictional-link-api-key"],
        ["fictional-user", nil]].each do |username, key|
        configure_api(key, username)
        session.get("/models/#{model.to_param}")
        assert_equal 200, session.response.status
        document = Nokogiri::HTML(session.response.body)
        model_links = document.css('a[href]').select { |link| link.text.strip == "Link to Cults3D" }
        expected_count = username.present? && key.present? ? 1 : 0
        assert_equal expected_count, model_links.size
        provider_link = document.css('#providers-menu a.dropdown-item').find { |link| link.text.strip == "Cults3D" }
        refute_nil provider_link
        assert_equal "/manyfold_cults3d", provider_link["href"].delete_suffix("/")
        session.get(provider_link["href"])
        assert_equal 200, session.response.status
      end
      assert_empty link_jobs
      assert_empty model.links.reload
    end
  end

  def test_link_manual_entry_queues_only_the_selected_existing_model
    configure_api("fictional-link-api-key")
    with_native_model do |model|
      ["", "/manyfold"].each do |prefix|
        session = browser(@users.first)
        form = get_link_form(session, model, prefix)
        assert_equal "", form.at_css('input[name="source"]')["value"].to_s
        document = Nokogiri::HTML(session.response.body)
        assert_empty document.css('a[href]').select { |link| link.text.strip == "Use this model" }
        ids_before = ::Model.order(:id).pluck(:id)
        ["92001", "https://cults3d.com/en/3d-model/art/fictional-model-92001"].each do |source|
          post_link(session, model, source, form, prefix)
          assert_equal 303, session.response.status
          assert_equal "#{session.request.base_url}#{prefix}/models/#{model.to_param}", session.response.location
          refute_empty link_jobs, "No sync job was queued with mount prefix #{prefix.inspect}."
          expected = ManyfoldCults3d::Source.new(source).id
          assert_includes link_jobs.map { |job| job[:args] }, [model.id, @users.first.id, expected]
          assert link_jobs.all? { |job| job[:args].first(2) == [model.id, @users.first.id] }
          assert_equal ids_before, ::Model.order(:id).pluck(:id)
          assert_empty model.links.reload
          form = get_link_form(session, model, prefix)
        end
      end
    end
  end

  def test_link_rejects_invalid_sources_missing_key_and_csrf_without_mutations
    configure_api("fictional-link-api-key")
    with_native_model do |model|
      session = browser(@users.first)
      ids_before = ::Model.order(:id).pluck(:id)
      invalid_sources = ["", "0", "not a slug!", "https://example.invalid/en/3d-model/art/fictional-model-92001",
        "https://www.cults3d.com.example.invalid/en/3d-model/art/fictional-model-92001",
        "https://user@cults3d.com/en/3d-model/art/fictional-model-92001", ["92001"]]
      invalid_sources.each do |source|
        form = get_link_form(session, model)
        post_link(session, model, source, form)
        assert_equal 422, session.response.status
        expected = source.is_a?(String) ? source : ""
        assert_equal expected, link_form_document(session).at_css('input[name="source"]')["value"].to_s
        assert_equal "Copper Dragon", Nokogiri::HTML(session.response.body).at_css('input[name="match_q"]')["value"]
        assert_empty link_jobs
        assert_empty model.links.reload
        assert_equal ids_before, ::Model.order(:id).pluck(:id)
      end

      SiteSettings.cults3d_api_key = "  "
      form = get_link_form(session, model)
      post_link(session, model, "92001", form)
      assert_equal 422, session.response.status
      assert_equal "92001", link_form_document(session).at_css('input[name="source"]')["value"]
      assert_empty link_jobs
      assert_empty model.links.reload

      configure_api("fictional-link-api-key")
      session.post("/manyfold_cults3d/link", params: {model_id: model.to_param, source: "92001"},
        headers: {"HTTP_ORIGIN" => session.request.base_url})
      assert_equal 422, session.response.status
      assert_empty link_jobs
      assert_empty model.links.reload
      assert_equal ids_before, ::Model.order(:id).pluck(:id)
    end
  end

  def test_link_requires_admin_existing_model_and_sync_permission
    configure_api("fictional-link-api-key")
    with_native_model do |model|
      session = browser(@users.last)
      session.get("/models/#{model.to_param}")
      assert_equal 200, session.response.status
      document = Nokogiri::HTML(session.response.body)
      refute document.css('a[href]').any? { |link| link.text.include?("Link to Cults3D") }
      token = document.at_css('meta[name="csrf-token"]')["content"]
      origin = session.request.base_url
      session.get("/manyfold_cults3d/link", params: {model_id: model.to_param})
      assert_equal 404, session.response.status
      session.post("/manyfold_cults3d/link", params: {model_id: model.to_param, source: "92001", authenticity_token: token},
        headers: {"HTTP_ORIGIN" => origin})
      assert_equal 404, session.response.status
      assert_empty link_jobs
      assert_empty model.links.reload

      session = browser(@users.first)
      form = get_link_form(session, model)
      token = form.at_css('input[name="authenticity_token"]')["value"]
      origin = session.request.base_url
      session.get("/manyfold_cults3d/link", params: {model_id: "missing-fictional-model"})
      assert_equal 404, session.response.status
      session.post("/manyfold_cults3d/link", params: {model_id: "missing-fictional-model", source: "92001", authenticity_token: token},
        headers: {"HTTP_ORIGIN" => origin})
      assert_equal 404, session.response.status

      model.federails_actor.update_columns(local: false)
      refute ::ModelPolicy.new(@users.first, model.reload).sync?
      session.get("/manyfold_cults3d/link", params: {model_id: model.to_param})
      assert_equal 404, session.response.status
      session.post("/manyfold_cults3d/link", params: {model_id: model.to_param, source: "92001", authenticity_token: token},
        headers: {"HTTP_ORIGIN" => origin})
      assert_equal 404, session.response.status
      assert_empty link_jobs
      assert_empty model.links.reload
    end
  end

  def test_link_sync_updates_metadata_without_creating_models_or_moving_files
    configure_api("fictional-link-api-key")
    with_native_model do |model|
      model.update!(tag_list: ["existing"])
      ids_before = ::Model.order(:id).pluck(:id)
      path_before = model.path
      public_id_before = model.public_id
      owners_before = model.owners.order(:id).pluck(:id)
      client = FakeLinkClient.new(fake_link_payload)
      with_link_client(client) do
        2.times { ManyfoldCults3d::SyncJob.perform_now(model.id, @users.first.id, "92001") }
      end
      assert_equal [creation_identifier(92001), creation_identifier(92001)], client.calls
      model.reload
      assert_equal "Linked Copper Dragon", model.name
      assert_includes model.notes, "Fictional description."
      assert_equal ["example", "existing", "linked"], model.tag_list.sort
      assert_equal "CC-BY-4.0", model.license
      assert_equal "example-linking-studio", model.creator.name
      assert_equal path_before, model.path
      assert_equal public_id_before, model.public_id
      assert_equal owners_before, model.owners.order(:id).pluck(:id)
      assert_equal model.name.parameterize, model.slug
      refute_equal fake_link_payload["slug"], model.slug
      assert_equal ids_before, ::Model.order(:id).pluck(:id)
      assert_equal 1, model.links.size
      link = model.links.first
      assert_equal fake_link_payload["url"], link.url
      refute_nil link.synced_at
      assert_equal [], model.model_files.to_a
    end
  end

  def test_link_sync_rechecks_permissions_before_api_calls_and_link_creation
    configure_api("fictional-link-api-key")
    with_native_model do |model|
      client = FakeLinkClient.new(fake_link_payload)
      original = model.attributes
      with_link_client(client) do
        ManyfoldCults3d::SyncJob.perform_now(model.id, @users.last.id, "92001")
        assert_empty client.calls
        assert_empty model.links.reload
        assert_equal original, model.reload.attributes
        model.federails_actor.update_columns(local: false)
        ManyfoldCults3d::SyncJob.perform_now(model.id, @users.first.id, "92001")
      end
      assert_empty client.calls
      assert_empty model.links.reload
      assert_equal original, model.reload.attributes
    end
  end

  def test_link_sync_rejects_an_unexpected_api_model_before_creating_a_link
    configure_api("fictional-link-api-key")
    with_native_model do |model|
      original = model.attributes
      client = FakeLinkClient.new(fake_link_payload.merge("identifier" => creation_identifier(92099)))
      with_link_client(client) do
        ManyfoldCults3d::SyncJob.perform_now(model.id, @users.first.id, "92001")
      end
      assert_equal [creation_identifier(92001)], client.calls
      assert_empty model.links.reload
      assert_equal original, model.reload.attributes
    end
  end

  private

  def save_link_examples
    entries = [model_entry(92001, name: "Copper Dragon"), model_entry(92002, name: "Clockwork Badger"),
      model_entry(92003, name: "Unrelated Desert Castle")]
    ManyfoldCults3d::Inventory.attributes(entries).each { |attributes| library_models.create!(attributes) }
  end

  def with_link_client(client)
    with_api_client(client) { yield }
  end

  def with_native_model(name: "Copper Dragon")
    creators_before = ::Creator.pluck(:id)
    tags_before = ActsAsTaggableOn::Tag.pluck(:id)
    adapter = ActiveJob::Base.queue_adapter
    jobs_before = adapter.enqueued_jobs.dup
    path = "fictional-link-model-#{SecureRandom.hex(8)}"
    FileUtils.mkdir_p(File.join(@library_path, path))
    model = ::Model.create!(library: @library, name: name, path: path, permission_preset: "member", owner: @users.first)
    yield model
  ensure
    model&.federails_actor&.update_columns(local: true) if model&.persisted?
    model&.destroy!
    ::Creator.where.not(id: creators_before).find_each(&:destroy!) if creators_before
    ActsAsTaggableOn::Tag.where.not(id: tags_before).destroy_all if tags_before
    adapter&.enqueued_jobs&.replace(jobs_before) if jobs_before
  end

  def get_link_form(session, model, prefix = "")
    session.get("/manyfold_cults3d/link", params: {model_id: model.to_param}, env: {"SCRIPT_NAME" => prefix})
    assert_equal 200, session.response.status
    link_form_document(session)
  end

  def link_form_document(session)
    form = Nokogiri::HTML(session.response.body).at_css('#cults3d-link-form')
    refute_nil form
    assert_equal "post", form["method"].downcase
    assert_equal "Link and sync", form.at_css('input[type="submit"]')["value"]
    form
  end

  def post_link(session, model, source, form, prefix = "")
    token = form.at_css('input[name="authenticity_token"]')["value"]
    session.post("/manyfold_cults3d/link", params: {model_id: model.to_param, source: source, match_q: "Copper Dragon", authenticity_token: token},
      env: {"SCRIPT_NAME" => prefix}, headers: {"HTTP_ORIGIN" => session.request.base_url})
  end

  def link_jobs
    ActiveJob::Base.queue_adapter.enqueued_jobs.select { |job| job[:job] == ManyfoldCults3d::SyncJob }
  end

  def fake_link_payload
    {"identifier" => creation_identifier(92001), "url" => "https://cults3d.com/en/3d-model/art/fictional-model-92001",
      "name" => "Linked Copper Dragon", "description" => "<p>Fictional description.</p>",
      "slug" => "fictional-model-92001", "path" => "unexpected/provider/path",
      "tags" => ["example", "linked"], "license" => {"spdxId" => "CC-BY-4.0"}, "illustrations" => [],
      "creator" => {"nick" => "example-linking-studio", "bio" => "",
        "url" => "https://cults3d.com/en/users/example-linking-studio", "imageUrl" => nil}}
  end
end
