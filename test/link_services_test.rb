# frozen_string_literal: true

require "minitest/autorun"
require "faraday"

class MyMiniFactoryLinkServicesTest < Minitest::Test
  Source = ManyfoldMyminifactory::Source
  ApiClient = ManyfoldMyminifactory::ApiClient
  Mapper = ManyfoldMyminifactory::MetadataMapper

  def self.runnable_methods
    super.sort
  end

  def test_source_accepts_only_bounded_ids_and_model_urls
    assert_equal "92001", Source.new(" 92001 ").id
    assert_equal Source::MAX_ID.to_s, Source.new(Source::MAX_ID).id
    assert_equal "92001", Source.new("https://www.myminifactory.com/object/3d-print-example-92001?tracking=example#part").id
    assert_equal "92001", Source.new("http://myminifactory.com/object/example-92001/").id

    ["0", "-1", "01", "1.0", "1e5", (Source::MAX_ID + 1).to_s, "9" * 100,
      "https://myminifactory.com.example.invalid/object/example-92001",
      "https://example.invalid/object/example-92001",
      "https://user:password@www.myminifactory.com/object/example-92001",
      "https://www.myminifactory.com:80/object/example-92001",
      "http://www.myminifactory.com:443/object/example-92001",
      "ftp://www.myminifactory.com/object/example-92001",
      "https://www.myminifactory.com/users/example-92001",
      "https://www.myminifactory.com/object/example-92001/files", "../92001"].each do |input|
      assert_raises(Source::Invalid, input) { Source.new(input) }
    end
  end

  def test_source_canonical_url_checks_identity_and_removes_tracking
    payload = {"id" => 92001, "url" => "http://myminifactory.com/object/3d-print-example-92001/?tracking=example#part"}
    assert_equal "https://www.myminifactory.com/object/3d-print-example-92001", Source.canonical_url(payload)
    assert_raises(Source::Invalid) { Source.canonical_url(payload.merge("id" => 92002)) }
    ["92001", nil, "file:///object/example-92001", "https://example.invalid/object/example-92001"].each do |url|
      assert_raises(Source::Invalid) { Source.canonical_url(payload.merge("url" => url)) }
    end
    assert_raises(Source::Invalid) { Source.canonical_url({"id" => 92001}) }
  end

  def test_api_client_uses_the_configured_key_without_account_credentials
    client, requests = api_client(api_key: " example-api-key ")
    assert_equal({"id" => 92001, "name" => "Example model"}, client.object("92001"))
    assert_equal 1, requests.length
    assert_equal({"key" => "example-api-key"}, requests.first.params)
    assert_equal "application/json", requests.first.request_headers["Accept"]
    refute requests.first.request_headers.key?("Authorization")
  end

  def test_api_client_rejects_invalid_ids_and_missing_key_without_requesting
    client, requests = api_client
    [0, -1, "01", "1.0", "92001/other", Source::MAX_ID + 1].each do |id|
      assert_raises(ApiClient::InvalidObjectId) { client.object(id) }
    end
    assert_empty requests
    client, requests = api_client(api_key: " \t ")
    assert_raises(ApiClient::ConfigurationError) { client.object("92001") }
    assert_empty requests
  end

  def test_api_client_rejects_http_errors_and_invalid_responses
    {401 => ApiClient::AuthenticationError, 403 => ApiClient::AuthenticationError,
      404 => ApiClient::NotFound, 429 => ApiClient::RateLimited,
      500 => ApiClient::Unavailable}.each do |status, error_class|
      client, = api_client(status: status)
      error = assert_raises(error_class) { client.object("92001") }
      refute_includes error.message, "example-api-key"
    end
    [[], nil, {"id" => 92002}, {"id" => "92001/other"}].each do |body|
      client, = api_client(body: body)
      assert_raises(ApiClient::InvalidResponse) { client.object("92001") }
    end
    client, = api_client(raw_body: "{broken")
    assert_raises(ApiClient::InvalidResponse) { client.object("92001") }
  end

  def test_api_client_reports_network_failure_without_exposing_credentials
    client, = api_client(network_error: true)
    error = assert_raises(ApiClient::Unavailable) { client.object("92001") }
    refute_includes error.message, "example-api-key"
  end

  def test_metadata_mapping_uses_only_metadata_fields
    mapper = Mapper.new({"name" => " Example sculpture ",
      "description_html" => "<p>A <strong>fictional</strong> sculpture.</p>",
      "description" => "Plain fallback", "tags" => [" example ", "example", nil, "", "sculpture"],
      "license" => "CC-BY-4.0", "slug" => "incoming-slug", "path" => "incoming-path", "owner" => "incoming-owner"})
    assert_equal %i[license name notes tag_list], mapper.attributes.keys.sort
    assert_equal "Example sculpture", mapper.attributes[:name]
    assert_includes mapper.attributes[:notes], "**fictional**"
    assert_equal %w[example sculpture], mapper.attributes[:tag_list]
    assert_equal "CC-BY-4.0", mapper.attributes[:license]
    ["MyMiniFactory Store License", "MIT OR Apache-2.0", "not-a-license"].each do |license|
      refute Mapper.new({"license" => license}).attributes.key?(:license)
    end
  end

  def test_missing_metadata_and_empty_html_are_safe
    assert_equal({}, Mapper.new({}).attributes)
    assert_empty Mapper.new({}).images
    assert_nil Mapper.new({}).designer
    [" ", "<p></p>", "<p>&nbsp;</p>"].each do |html|
      mapper = Mapper.new({"description_html" => html, "description" => "Fictional fallback"})
      assert_equal({notes: "Fictional fallback"}, mapper.attributes)
    end
  end

  def test_optional_designer_fields_are_normalized_for_the_host
    mapper = Mapper.new({"designer" => {"username" => " example studio ", "name" => " ", "bio" => nil,
      "profile_url" => "https://myminifactory.com/users/example%20studio/?tracking=example#part",
      "avatar_url" => "http://cdn.example.invalid/avatar.jpg",
      "cover_url" => "https://cdn.example.invalid/cover.jpg"}})
    assert_equal "example studio", mapper.designer["username"]
    assert_equal "example studio", mapper.designer["name"]
    assert_equal "", mapper.designer["bio"]
    assert_equal "https://www.myminifactory.com/users/example%20studio", mapper.designer["profile_url"]
    assert_nil mapper.designer["avatar_url"]
    assert_equal "https://cdn.example.invalid/cover.jpg", mapper.designer["cover_url"]
    fallback = Mapper.new({"designer" => {"username" => "example studio", "profile_url" => "https://example.invalid/users/studio"}})
    assert_equal "https://www.myminifactory.com/users/example%20studio", fallback.designer["profile_url"]
    [nil, "example", {"name" => "Example"}, {"username" => 1}, {"username" => "!!!"}].each do |designer|
      assert_nil Mapper.new({"designer" => designer}).designer
    end
  end

  def test_images_validate_urls_and_preserve_primary_identity_after_filename_collisions
    primary_url = "https://cdn.example.invalid/second/front%20view.jpg"
    mapper = Mapper.new({"images" => [
      {"original" => {"url" => "https://cdn.example.invalid/first/front_view.jpg"}},
      {"is_primary" => true, "original" => {"url" => primary_url}},
      {"original" => {"url" => primary_url}},
      {"original" => {"url" => "https://cdn.example.invalid/file%00name.jpg"}},
      {"original" => {"url" => "http://cdn.example.invalid/unsafe.jpg"}},
      {"original" => {"url" => "https://user:password@cdn.example.invalid/unsafe.jpg"}},
      {"original" => {"url" => "https://cdn.example.invalid:444/unsafe.jpg"}},
      {"original" => {"url" => "not a URL"}}, nil],
      "files" => [{"filename" => "model.stl", "download_url" => "https://cdn.example.invalid/model.stl"}],
      "archive_download_url" => "https://cdn.example.invalid/model.zip"})
    assert_equal %w[front_view.jpg front_view_2.jpg file_name.jpg], mapper.file_urls.map { |file| file[:filename] }
    primary = mapper.images.find { |image| image[:primary] }
    assert_equal "front_view_2.jpg", primary[:filename]
    assert_equal primary[:filename], mapper.file_urls.find { |file| file[:url] == primary_url }[:filename]
    refute mapper.file_urls.any? { |file| file[:filename].end_with?(".stl", ".zip") }
  end

  private

  def api_client(api_key: "example-api-key", status: 200, body: {"id" => 92001, "name" => "Example model"}, raw_body: nil, network_error: false)
    requests = []
    connection = Faraday.new do |builder|
      builder.response :json
      builder.adapter :test do |adapter|
        adapter.get("objects/92001") do |environment|
          requests << environment
          raise Faraday::TimeoutError, "example-api-key should not be exposed" if network_error
          [status, {"Content-Type" => "application/json"}, raw_body || JSON.generate(body)]
        end
      end
    end
    [ApiClient.new(api_key: api_key, connection: connection), requests]
  end
end
