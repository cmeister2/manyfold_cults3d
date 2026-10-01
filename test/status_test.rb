# frozen_string_literal: true

abort "Run this test with bin/test in its disposable Manyfold container." unless
  ENV["MANYFOLD_MYMINIFACTORY_STATUS_TEST"] == "1" && defined?(Rails.application)

require "minitest/autorun"
require "action_dispatch/testing/integration"
require "active_job/queue_adapters/test_adapter"
require "warden/test/helpers"
require "nokogiri"
require "tmpdir"
require "fileutils"

ActiveJob::Base.queue_adapter = :test
Warden.test_mode!

class MyMiniFactoryStatusTest < Minitest::Test
  include Warden::Test::Helpers

  def setup
    @original_key = SiteSettings.myminifactory_api_key
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

  private

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
