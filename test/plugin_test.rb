# frozen_string_literal: true

abort "Run this test with bin/test in its disposable Manyfold container." unless
  ENV["MANYFOLD_CULTS3D_TEST"] == "1" && defined?(Rails.application)

require "minitest/autorun"
require "action_dispatch/testing/integration"
require "active_support/testing/time_helpers"
require "active_job/queue_adapters/test_adapter"
require "warden/test/helpers"
require "nokogiri"
require "tmpdir"
require "fileutils"
require "base64"

ActiveJob::Base.queue_adapter = :test
Warden.test_mode!

class Cults3DPluginTest < Minitest::Test
  include Warden::Test::Helpers
  include ActiveSupport::Testing::TimeHelpers

  IMPORT_KEY = "manyfold_cults3d_imported_at"
  SETTINGS = %w[cults3d_api_username cults3d_api_key default_library manyfold_cults3d_imported_at].freeze
  CREDENTIALS = %w[CULTS3D_USERNAME CULTS3D_API_KEY].freeze

  def self.runnable_methods
    super.sort
  end

  def setup
    @original_settings = SETTINGS.to_h do |key|
      setting = SiteSettings.find_by(var: key)
      [key, setting&.attributes]
    end
    @original_environment = CREDENTIALS.to_h { |key| [key, ENV.delete(key)] }
    SETTINGS.each { |key| SiteSettings.find_by(var: key)&.destroy! }
    @original_models = library_models.order(:id).map(&:attributes)
    library_models.delete_all
    @original_csrf = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    @library_path = Dir.mktmpdir("cults3d-status-test-")
    @library = Library.create!(name: "Status test", path: @library_path,
      storage_service: "filesystem", path_template: "{creator}/{modelName}")
    @users = [:administrator, :member].map do |role|
      identifier = SecureRandom.hex(8)
      User.create!(username: "status-#{identifier}", email: "#{identifier}@example.invalid",
        password: "Local-test-#{SecureRandom.hex(16)}", approved: true).tap { |user| user.add_role(role) }
    end
  end

  def teardown
    Warden.test_reset!
    @users&.each { |user| user.destroy! }
    @library&.destroy!
    @original_settings.each do |key, attributes|
      SiteSettings.find_by(var: key)&.destroy!
      SiteSettings.create!(attributes) if attributes
    end
    @original_environment.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    library_models.delete_all
    @original_models&.each { |attributes| library_models.create!(attributes) }
    ActionController::Base.allow_forgery_protection = @original_csrf
    FileUtils.remove_entry(@library_path) if @library_path && File.exist?(@library_path)
  end

  def test_real_host_navigation_for_both_roles_and_mount_prefixes
    assert_kind_of Rails::Engine, ManyfoldCults3d::Engine.instance
    expected_version = ENV["MANYFOLD_CULTS3D_EXPECTED_VERSION"]
    assert_equal expected_version, PluginManager.all.fetch("manyfold_cults3d").version.to_s if expected_version.present?
    assert_includes PluginManager.components_for(:navbar), Manyfold::ProviderMenu::Dropdown
    assert_includes PluginManager.components_for(:provider_menu), Components::ManyfoldCults3d::ProviderMenuItem
    @users.each do |user|
      [nil, "", "   ", "fictional-api-key"].each { |key| assert_navigation(user, key) }
    end
    [nil, "fictional-api-key"].each { |key| assert_navigation(@users.first, key, script_name: "/manyfold") }
  end

  def test_import_refreshes_the_api_library_without_accepting_pasted_json
    configure_api
    ["", "/manyfold"].each do |prefix|
      session = browser(@users.first)
      form = import_form(session, prefix)
      assert_empty form.css("textarea")
      submit = form.at_css('input[type="submit"], button[type="submit"]')
      assert_equal "Refresh library", submit["value"] || submit.text.strip
      client = FakeLibraryClient.new([model_entry(2001, name: "<example> & \u00e9")])
      with_api_client(client) { post_refresh(session, form, prefix) }
      assert_equal 1, client.calls
      assert_equal 303, session.response.status
      assert_equal "1 model imported.", session.request.flash[:notice]
      assert_equal "#{session.request.base_url}#{prefix}/manyfold_cults3d/", session.response.location
      assert_equal "<example> & \u00e9", library_models.find_by!(cults3d_id: creation_identifier(2001)).name
      assert_equal 1, library_models.count
      assert_status_summary(session, 1, Time.iso8601(SiteSettings.manyfold_cults3d_imported_at), prefix)
    end
  end

  def test_import_requires_admin_and_csrf_before_requesting_the_api
    configure_api
    session = browser(@users.first)
    form = import_form(session)
    client = FakeLibraryClient.new([model_entry(4001)])
    with_api_client(client) do
      session.post("/manyfold_cults3d/import", headers: {"HTTP_ORIGIN" => session.request.base_url})
      assert_equal 422, session.response.status
      assert_equal 0, client.calls
      assert_empty library_models.all
      assert_nil SiteSettings.manyfold_cults3d_imported_at
      post_refresh(session, form)
      assert_equal 303, session.response.status
      session = browser(@users.last)
      session.get("/manyfold_cults3d/")
      document = Nokogiri::HTML(session.response.body)
      assert_nil document.at_css('#cults3d-tabs a[href$="/import"]')
      token = document.at_css('meta[name="csrf-token"]')["content"]
      origin = session.request.base_url
      session.get("/manyfold_cults3d/import")
      assert_equal 404, session.response.status
      session.post("/manyfold_cults3d/import", params: {authenticity_token: token}, headers: {"HTTP_ORIGIN" => origin})
      assert_equal 404, session.response.status
      assert_equal 1, client.calls
      assert_equal [creation_identifier(4001)], library_models.pluck(:cults3d_id)
    end
  end

  def test_failed_refresh_preserves_rows_and_last_successful_import_time
    configure_api
    session = browser(@users.first)
    form = import_form(session)
    with_api_client(FakeLibraryClient.new([model_entry(5001)])) { post_refresh(session, form) }
    rows_before = library_models.order(:id).map(&:attributes)
    imported_at = SiteSettings.manyfold_cults3d_imported_at
    invalid = model_entry(5003, name: "   ")
    failures = [FakeLibraryClient.new([model_entry(5002), invalid]),
      FakeLibraryClient.new(ManyfoldCults3d::ApiClient::Error.new("Fictional API failure."))]
    failures.each do |client|
      form = import_form(session)
      with_api_client(client) { post_refresh(session, form) }
      assert_equal 422, session.response.status
      assert_equal rows_before, library_models.order(:id).map(&:attributes)
      assert_equal imported_at, SiteSettings.manyfold_cults3d_imported_at
      refute_nil Nokogiri::HTML(session.response.body).at_css('form[action$="/import"]')
    end
  end

  def test_import_updates_existing_rows_retains_absent_models_and_deduplicates_orders
    configure_api
    session = browser(@users.first)
    form = import_form(session)
    with_api_client(FakeLibraryClient.new([model_entry(6001), model_entry(6002)])) { post_refresh(session, form) }
    original_id = library_models.find_by!(cults3d_id: creation_identifier(6001)).id
    absent_model = library_models.find_by!(cults3d_id: creation_identifier(6002)).attributes
    updated = model_entry(6001, name: "Updated example model", added_at: "2025-02-01T12:00:00Z")
    updated.fetch("lines").first.fetch("creation")["tags"] = ["updated"]
    first_import = Time.current.utc.change(usec: 0)
    [first_import, first_import + 60].each do |imported_at|
      form = import_form(session)
      travel_to(imported_at) do
        with_api_client(FakeLibraryClient.new([updated, updated])) { post_refresh(session, form) }
      end
      assert_equal 303, session.response.status
      assert_equal "1 model imported.", session.request.flash[:notice]
      assert_equal 2, library_models.count
      refreshed = library_models.find_by!(cults3d_id: creation_identifier(6001))
      assert_equal original_id, refreshed.id
      assert_equal "Updated example model", refreshed.name
      assert_equal ["updated"], refreshed.tags
      assert_equal Time.utc(2025, 2, 1, 12), refreshed.library_added_at
      assert_equal absent_model, library_models.find_by!(cults3d_id: creation_identifier(6002)).attributes
      assert_equal imported_at, Time.iso8601(SiteSettings.manyfold_cults3d_imported_at)
      assert_status_summary(session, 2, imported_at)
    end
  end

  def test_empty_refresh_records_success_without_deleting_saved_models
    configure_api
    save_status_examples([model_entry(7001)])
    session = browser(@users.first)
    form = import_form(session)
    with_api_client(FakeLibraryClient.new([])) { post_refresh(session, form) }
    assert_equal 303, session.response.status
    assert_equal "0 models imported.", session.request.flash[:notice]
    assert_status_summary(session, 1, Time.iso8601(SiteSettings.manyfold_cults3d_imported_at))
  end

  def test_refresh_requires_both_credentials_without_changing_saved_rows
    save_status_examples([model_entry(7101)])
    rows_before = library_models.order(:id).map(&:attributes)
    imported_at = SiteSettings.manyfold_cults3d_imported_at
    [[nil, "fictional-api-key"], ["fictional-user", nil]].each do |username, key|
      configure_api(key, username)
      session = browser(@users.first)
      form = import_form(session)
      assert form.at_css('input[type="submit"]')["disabled"]
      post_refresh(session, form)
      assert_equal 422, session.response.status
      assert_equal rows_before, library_models.order(:id).map(&:attributes)
      assert_equal imported_at, SiteSettings.manyfold_cults3d_imported_at
    end
  end

  class FakeLibraryClient
    attr_reader :calls

    def initialize(result)
      @result = result
      @calls = 0
    end

    def library
      @calls += 1
      raise @result if @result.is_a?(Exception)
      Marshal.load(Marshal.dump(@result))
    end
  end

  private

  def configure_api(key = "fictional-api-key", username = "fictional-user")
    SiteSettings.cults3d_api_username = username
    SiteSettings.cults3d_api_key = key
  end

  def library_models
    ManyfoldCults3d::LibraryModel
  end

  def creation_identifier(id)
    Base64.strict_encode64("Creation/#{id}").delete("=")
  end

  def creation_slug(id)
    "fictional-model-#{id}"
  end

  # Fictional data only, matching the GraphQL order/line/creation nesting.
  def model_entry(id, name: "Example model #{id}", added_at: "2025-01-01T12:00:00Z")
    {"id" => "fictional-order-#{id}", "createdAt" => added_at,
      "lines" => [{"id" => "fictional-line-#{id}", "downloadUrl" => nil,
        "creation" => {"identifier" => creation_identifier(id), "slug" => creation_slug(id),
          "url" => "https://cults3d.com/en/3d-model/art/#{creation_slug(id)}", "name" => name,
          "tags" => ["example", "test"], "creator" => {"nick" => "example-creator"}}}]}
  end

  def browser(user)
    Warden.test_reset!
    login_as(user, scope: :user)
    ActionDispatch::Integration::Session.new(Rails.application).tap do |session|
      session.host!(PublicUrl.hostname)
      session.https! if Rails.application.config.assume_ssl
    end
  end

  def import_form(session, prefix = "")
    session.get("/manyfold_cults3d/import", env: {"SCRIPT_NAME" => prefix})
    assert_equal 200, session.response.status
    form = Nokogiri::HTML(session.response.body).at_css('form[action$="/import"]')
    refute_nil form
    assert_equal "#{prefix}/manyfold_cults3d/import", form["action"]
    form
  end

  def post_refresh(session, form, prefix = "")
    native_ids = ::Model.order(:id).pluck(:id)
    token = form.at_css('input[name="authenticity_token"]')["value"]
    session.post("/manyfold_cults3d/import", params: {authenticity_token: token},
      env: {"SCRIPT_NAME" => prefix}, headers: {"HTTP_ORIGIN" => session.request.base_url})
    assert_equal native_ids, ::Model.order(:id).pluck(:id), "Import changed native Manyfold models."
  end

  def with_api_client(client)
    singleton = ManyfoldCults3d::ApiClient.singleton_class
    original = ManyfoldCults3d::ApiClient.method(:new)
    own_constructor = singleton.instance_methods(false).include?(:new)
    singleton.send(:define_method, :new) { |*arguments, **options, &block| client }
    yield
  ensure
    own_constructor ? singleton.send(:define_method, :new, original) : singleton.send(:remove_method, :new)
  end

  def assert_status_summary(session, count, imported_at, prefix = "")
    document = status_document(session, prefix)
    assert_equal ["#{count} models in database", "Imported at #{imported_at.strftime('%Y-%m-%d %H:%M:%S %Z')}"],
      document.css("#cults3d-import-summary p").map { |paragraph| paragraph.text.strip }
    assert_equal count, document.css("#cults3d-models tbody tr").size
  end

  def assert_navigation(user, key, script_name: "")
    configure_api(key)
    session = browser(user)
    environment = {"SCRIPT_NAME" => script_name}
    session.get("/models", env: environment)
    assert_equal 200, session.response.status
    document = Nokogiri::HTML(session.response.body)
    toggle = document.at_css("#main-navbar #nav-link-providers")
    refute_nil toggle
    assert_equal "Providers", toggle.text.strip
    assert_equal "dropdown", toggle["data-bs-toggle"]
    assert_equal "providers-menu", toggle["aria-controls"]
    refute_nil toggle.at_css(".bi-plug")
    assert_equal ["Cults3D"], document.css("#providers-menu a.dropdown-item").map { |link| link.text.strip }
    link = document.at_css("#providers-menu a.dropdown-item")
    assert_equal "#{script_name}/manyfold_cults3d", link["href"].delete_suffix("/")
    refute_nil link.at_css(".bi-box-seam")
    session.get(link["href"].delete_prefix(script_name), env: environment)
    assert_equal 200, session.response.status
    document = Nokogiri::HTML(session.response.body)
    hrefs = document.css("#main-navbar a[href]").map { |item| item["href"] }
    assert_includes hrefs, "#{script_name}/dashboard"
    assert_includes hrefs, "#{script_name}/models"
  end
end

Dir[File.join(__dir__, "*_test.rb")].sort.each do |path|
  require path unless path == __FILE__
end
