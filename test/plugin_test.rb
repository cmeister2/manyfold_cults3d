# frozen_string_literal: true

abort "Run this test with bin/test in its disposable Manyfold container." unless
  ENV["MANYFOLD_MYMINIFACTORY_TEST"] == "1" && defined?(Rails.application)

require "minitest/autorun"
require "action_dispatch/testing/integration"
require "active_job/queue_adapters/test_adapter"
require "warden/test/helpers"
require "nokogiri"
require "tmpdir"
require "fileutils"

ActiveJob::Base.queue_adapter = :test
Warden.test_mode!

class MyMiniFactoryPluginTest < Minitest::Test
  include Warden::Test::Helpers

  IMPORT_KEY = "manyfold_myminifactory_import_json"

  def self.test_order
    :alpha
  end

  def setup
    @original_key = SiteSettings.myminifactory_api_key
    @original_default_library = SiteSettings.default_library
    @original_import = SiteSettings.find_by(var: IMPORT_KEY)
    @original_json = @original_import&.value
    @original_csrf = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    @library_path = Dir.mktmpdir("myminifactory-status-test-")
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
    SiteSettings.myminifactory_api_key = @original_key
    SiteSettings.default_library = @original_default_library
    if @original_import
      SiteSettings.manyfold_myminifactory_import_json = @original_json
    else
      SiteSettings.find_by(var: IMPORT_KEY)&.destroy!
    end
    ActionController::Base.allow_forgery_protection = @original_csrf
    FileUtils.remove_entry(@library_path) if @library_path && File.exist?(@library_path)
  end

  def test_real_host_navigation_and_status_for_both_roles_and_all_settings
    assert_kind_of Rails::Engine, ManyfoldMyminifactory::Engine.instance
    assert_includes PluginManager.components_for(:navbar), Components::ManyfoldMyminifactory::NavLink

    @users.each do |user|
      [nil, "", "   ", "local-test-api-key"].each do |key|
        assert_navigation(user, key)
      end
    end
    [nil, "local-test-api-key"].each { |key| assert_navigation(@users.first, key, script_name: "/manyfold") }
  end

  def test_import_saves_exact_json_and_retains_invalid_input
    json = " \n" + JSON.pretty_generate({"items" => [{"id" => 123, "name" => "<example> & \u00e9",
      "enabled" => false, "notes" => nil}]}) + "\n "
    ["", "/manyfold"].each do |prefix|
      session = browser(@users.first)
      form = import_form(session, prefix)
      assert_equal 1, form.css("textarea").size
      assert_equal ["submit"], form.css('input:not([type="hidden"])').map { |input| input["type"] }
      assert_equal "Save", form.at_css('input[type="submit"]')["value"]
      post_json(session, json, form, prefix)
      assert_equal 303, session.response.status
      assert_equal "#{session.request.base_url}#{prefix}/manyfold_myminifactory/import", session.response.location
      assert_equal json, saved_json
      form = import_form(session, prefix)
      assert_equal json, form.at_css("textarea").text.delete_prefix("\n")

      ["{broken", "", ["unexpected", "array"]].each do |invalid|
        post_json(session, invalid, form, prefix)
        assert_equal 422, session.response.status
        assert_equal json, saved_json
        document = Nokogiri::HTML(session.response.body)
        assert_includes document.text, "Invalid JSON."
        expected = invalid.is_a?(String) ? invalid : ""
        assert_equal expected, document.at_css("textarea").text.delete_prefix("\n")
        form = document.at_css('form:has(textarea[name="json"])')
      end
    end
  end

  def test_import_requires_admin_and_csrf_token
    original = '{"saved":true}'
    SiteSettings.manyfold_myminifactory_import_json = original
    session = browser(@users.first)
    import_form(session)
    session.post("/manyfold_myminifactory/import", params: {json: '{"changed":true}'},
      headers: {"HTTP_ORIGIN" => session.request.base_url})
    assert_equal 422, session.response.status
    assert_equal original, saved_json

    session = browser(@users.last)
    session.get("/manyfold_myminifactory/")
    assert_equal 200, session.response.status
    document = Nokogiri::HTML(session.response.body)
    assert_nil document.at_css('main nav a[href$="/import"]')
    token = document.at_css('meta[name="csrf-token"]')["content"]
    origin = session.request.base_url
    session.get("/manyfold_myminifactory/import")
    assert_equal 404, session.response.status
    session.post("/manyfold_myminifactory/import", params: {json: '{"changed":true}', authenticity_token: token},
      headers: {"HTTP_ORIGIN" => origin})
    assert_equal 404, session.response.status
    assert_equal original, saved_json
  end

  private

  def browser(user)
    Warden.test_reset!
    login_as(user, scope: :user)
    ActionDispatch::Integration::Session.new(Rails.application).tap do |session|
      session.host!(PublicUrl.hostname)
      session.https! if Rails.application.config.assume_ssl
    end
  end

  def import_form(session, prefix = "")
    environment = {"SCRIPT_NAME" => prefix}
    session.get("/manyfold_myminifactory/", env: environment)
    assert_equal 200, session.response.status
    document = Nokogiri::HTML(session.response.body)
    link = document.at_css('main nav a[href$="/import"]')
    refute_nil link
    assert_equal "#{prefix}/manyfold_myminifactory/import", link["href"]
    session.get(link["href"].delete_prefix(prefix), env: environment)
    assert_equal 200, session.response.status
    form = Nokogiri::HTML(session.response.body).at_css('form:has(textarea[name="json"])')
    refute_nil form
    assert_equal "#{prefix}/manyfold_myminifactory/import", form["action"]
    form
  end

  def post_json(session, json, form, prefix = "")
    token = form.at_css('input[name="authenticity_token"]')["value"]
    session.post("/manyfold_myminifactory/import", params: {json: json, authenticity_token: token},
      env: {"SCRIPT_NAME" => prefix}, headers: {"HTTP_ORIGIN" => session.request.base_url})
  end

  def saved_json
    SiteSettings.find_by!(var: IMPORT_KEY).reload.value
  end

  def assert_navigation(user, key, script_name: "")
    SiteSettings.myminifactory_api_key = key
    Warden.test_reset!
    login_as(user, scope: :user)
    session = ActionDispatch::Integration::Session.new(Rails.application)
    session.host!(PublicUrl.hostname)
    session.https! if Rails.application.config.assume_ssl
    environment = {"SCRIPT_NAME" => script_name}

    session.get("/models", env: environment)
    assert_equal 200, session.response.status
    assert_equal script_name, session.request.script_name
    document = Nokogiri::HTML(session.response.body)
    link = document.css("#main-navbar a.nav-link").find { |element| element.text.strip == "MyMiniFactory" }
    refute_nil link, "MyMiniFactory was missing from the host navbar."
    assert_equal "#{script_name}/manyfold_myminifactory", link["href"].delete_suffix("/")
    refute_nil link.at_css(".bi-box-seam"), "The navbar link was missing its icon."

    # A reverse proxy strips its mount prefix from PATH_INFO and supplies SCRIPT_NAME.
    session.get(link["href"].delete_prefix(script_name), env: environment)
    assert_equal 200, session.response.status
    document = Nokogiri::HTML(session.response.body)
    plugin_link = document.css("#main-navbar a.nav-link").find { |element| element.text.strip == "MyMiniFactory" }
    refute_nil plugin_link
    assert_equal link["href"], plugin_link["href"], "The plugin navbar link changed its mount prefix."
    message = key.present? ? "myminifactory is linked" : "myminifactory not linked"
    paragraphs = document.css("main p").map { |paragraph| paragraph.text.strip }
    assert_includes paragraphs, message
    refute_includes paragraphs, key.present? ? "myminifactory not linked" : "myminifactory is linked"
    hrefs = document.css("#main-navbar a[href]").map { |element| element["href"] }
    assert_includes hrefs, "#{script_name}/dashboard"
    assert_includes hrefs, "#{script_name}/models"
  end
end
