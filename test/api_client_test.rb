# frozen_string_literal: true

require "minitest/autorun"
require "base64"
require "json"
require "faraday"

# Fictional responses exercise the actual Faraday request and JSON middleware.
class Cults3DApiClientTest < Minitest::Test
  Client = ManyfoldCults3d::ApiClient
  USERNAME = "fictional-api-username"
  API_KEY = "fictional-sensitive-api-key"

  def test_slug_lookup_posts_graphql_json_with_basic_auth
    payload = creation(42)
    client, requests, stubs = stub_client({"data" => {"creation" => payload}})

    assert_equal payload, client.object("copper-dragon-42")
    assert_equal 1, requests.length
    request = requests.first
    assert_equal Client::BASE_URL, request[:url]
    assert_equal "Basic #{Base64.strict_encode64("#{USERNAME}:#{API_KEY}")}", request[:headers]["Authorization"]
    assert_equal "application/json", request[:headers]["Accept"]
    assert_equal "application/json", request[:headers]["Content-Type"]
    assert_equal({"slug" => "copper-dragon-42"}, request[:body]["variables"])
    assert_includes request[:body]["query"], "creation(slug: $slug)"
    assert_includes request[:body]["query"], "imageUrl(version: DEFAULT)"
    refute_includes JSON.generate(request[:body]), API_KEY
    stubs.verify_stubbed_calls
  end

  def test_numeric_and_global_identifiers_use_the_encoded_batch_filter
    ["42", identifier(42), Base64.strict_encode64("Creation/42"), "https://cults3d.com/:42"].each do |source|
      payload = creation(42)
      client, requests, stubs = stub_client({"data" => {"creationsBatch" => {"total" => 1, "results" => [payload]}}})
      assert_equal payload, client.object(source)
      assert_equal({"identifier" => identifier(42)}, requests.first[:body]["variables"])
      assert_includes requests.first[:body]["query"], "creationsBatch(ids: [$identifier], safe: false, limit: 1)"
      stubs.verify_stubbed_calls
    end
  end

  def test_model_url_uses_its_slug_without_query_or_fragment
    client, requests, stubs = stub_client({"data" => {"creation" => creation(42)}})
    client.object("https://cults3d.com/en/3d-model/art/copper-dragon-42?utm_source=example#photos")
    assert_equal({"slug" => "copper-dragon-42"}, requests.first[:body]["variables"])
    stubs.verify_stubbed_calls
  end

  def test_lookup_rejects_ignored_identifier_filters_and_wrong_model_identity
    responses = [
      {"creationsBatch" => {"total" => 3_000_000, "results" => [creation(43)]}},
      {"creationsBatch" => {"total" => 1, "results" => [creation(43)]}},
      {"creationsBatch" => {"total" => 1, "results" => []}},
      {"creationsBatch" => {"total" => 0, "results" => [creation(42)]}},
      {"creationsBatch" => {"total" => "1", "results" => [creation(42)]}}
    ]
    responses.each do |data|
      client, = stub_client({"data" => data})
      assert_raises(Client::InvalidResponse) { client.object("42") }
    end
    client, = stub_client({"data" => {"creation" => creation(43)}})
    assert_raises(Client::InvalidResponse) { client.object("copper-dragon-42") }
  end

  def test_not_found_for_null_slug_and_empty_identifier_batch
    [{source: "copper-dragon-42", data: {"creation" => nil}},
     {source: "42", data: {"creationsBatch" => {"total" => 0, "results" => []}}}].each do |example|
      client, = stub_client({"data" => example[:data]})
      assert_raises(Client::NotFound) { client.object(example[:source]) }
    end
  end

  def test_invalid_lookup_never_sends_a_request
    ["", "0", "-2", "not a slug!", "https://example.invalid/:42"].each do |source|
      client, requests, = stub_client
      assert_raises(Client::InvalidObjectId) { client.object(source) }
      assert_empty requests
    end
  end

  def test_library_fetches_more_than_one_hundred_orders_using_offsets
    orders = (1..103).map { |id| {"id" => "Order/#{id}", "lines" => []} }
    client, requests, stubs = stub_client(library_page(103, orders.first(100)), library_page(103, orders.drop(100)))
    assert_equal orders, client.library
    assert_equal [{"limit" => 100, "offset" => 0}, {"limit" => 100, "offset" => 100}],
      requests.map { |request| request[:body]["variables"] }
    assert requests.all? { |request| request[:body]["query"].include?("ordersBatch") }
    stubs.verify_stubbed_calls
  end

  def test_empty_library_is_a_successful_single_page
    client, requests, stubs = stub_client(library_page(0, []))
    assert_empty client.library
    assert_equal 1, requests.length
    stubs.verify_stubbed_calls
  end

  def test_library_rejects_invalid_or_changing_totals_and_oversized_pages
    [-1, Client::MAX_ORDERS + 1, "1", nil, true].each do |total|
      client, = stub_client(library_page(total, []))
      assert_raises(Client::InvalidResponse) { client.library }
    end
    orders = (1..100).map { |id| {"id" => "Order/#{id}"} }
    client, = stub_client(library_page(101, orders), library_page(102, [{"id" => "Order/101"}]))
    assert_raises(Client::InvalidResponse) { client.library }
    client, = stub_client(library_page(101, orders + [{"id" => "Order/101"}]))
    assert_raises(Client::InvalidResponse) { client.library }
    client, = stub_client(library_page(0, [{"id" => "Order/1"}]))
    assert_raises(Client::InvalidResponse) { client.library }
  end

  def test_library_rejects_duplicates_empty_incomplete_pages_and_invalid_orders
    [[{"id" => "Order/1"}, {"id" => "Order/1"}], [{"id" => 1}], [{}], [nil]].each do |orders|
      client, = stub_client(library_page(orders.length, orders))
      assert_raises(Client::InvalidResponse) { client.library }
    end
    client, = stub_client(library_page(1, []))
    assert_raises(Client::InvalidResponse) { client.library }
    client, = stub_client(library_page(2, [{"id" => "Order/1"}]), library_page(2, []))
    assert_raises(Client::InvalidResponse) { client.library }
    client, = stub_client(library_page(2, [{"id" => "Order/1"}]), library_page(2, [{"id" => "Order/1"}]))
    assert_raises(Client::InvalidResponse) { client.library }
  end

  def test_graphql_errors_discard_partial_library_and_redact_server_messages
    first = library_page(2, [{"id" => "Order/1"}])
    partial = library_page(2, [{"id" => "Order/2"}]).merge("errors" => [{"message" => "#{USERNAME}:#{API_KEY}"}])
    client, = stub_client(first, partial)
    error = assert_raises(Client::InvalidResponse) { client.library }
    assert_redacted(error)
    [nil, {"errors" => "secret #{API_KEY}", "data" => {}}, {"data" => nil}, {"data" => {}}].each do |payload|
      client, = stub_client(payload)
      assert_raises(Client::InvalidResponse) { client.object("42") }
    end
  end

  def test_missing_authenticated_account_is_an_authentication_error
    client, = stub_client({"data" => {"myself" => nil}})
    assert_raises(Client::AuthenticationError) { client.library }
  end

  def test_both_credentials_are_required_before_any_request
    [["", API_KEY], [USERNAME, "  "], [nil, nil]].each do |username, api_key|
      client, requests, = stub_client(username: username, api_key: api_key)
      assert_raises(Client::ConfigurationError) { client.library }
      assert_empty requests
    end
  end

  def test_http_errors_return_specific_safe_errors
    {401 => Client::AuthenticationError, 403 => Client::AuthenticationError,
     404 => Client::NotFound, 429 => Client::RateLimited, 500 => Client::Unavailable}.each do |status, error_class|
      client, = stub_client({"message" => "#{USERNAME}:#{API_KEY}"}, status: status)
      assert_redacted(assert_raises(error_class) { client.library })
    end
  end

  def test_network_and_json_parse_errors_redact_secrets_and_cause
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post(Client::BASE_URL) { raise Faraday::ConnectionFailed, "#{USERNAME}:#{API_KEY}" }
    end
    connection = Faraday.new { |builder| builder.response :json; builder.adapter :test, stubs }
    client = Client.new(username: USERNAME, api_key: API_KEY, connection: connection)
    assert_redacted(assert_raises(Client::Unavailable) { client.library })
    client, = stub_client("broken JSON #{API_KEY}", raw: true)
    assert_redacted(assert_raises(Client::InvalidResponse) { client.library })
  end

  private

  def identifier(id)
    Base64.strict_encode64("Creation/#{id}").delete("=")
  end

  def creation(id)
    {"identifier" => identifier(id), "slug" => "copper-dragon-#{id}", "name" => "Copper Dragon",
     "url" => "https://cults3d.com/en/3d-model/art/copper-dragon-#{id}"}
  end

  def library_page(total, results)
    {"data" => {"myself" => {"ordersBatch" => {"total" => total, "results" => results}}}}
  end

  def stub_client(*payloads, username: USERNAME, api_key: API_KEY, status: 200, raw: false)
    requests = []
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      payloads.each do |payload|
        stub.post(Client::BASE_URL) do |environment|
          requests << {url: environment.url.to_s, headers: environment.request_headers.to_h,
                       body: JSON.parse(environment.body)}
          [status, {"Content-Type" => "application/json"}, raw ? payload : JSON.generate(payload)]
        end
      end
    end
    connection = Faraday.new { |builder| builder.response :json; builder.adapter :test, stubs }
    [Client.new(username: username, api_key: api_key, connection: connection), requests, stubs]
  end

  def assert_redacted(error)
    refute_includes error.message, USERNAME
    refute_includes error.message, API_KEY
    refute_includes error.message, Base64.strict_encode64("#{USERNAME}:#{API_KEY}")
    assert_nil error.cause
  end
end
