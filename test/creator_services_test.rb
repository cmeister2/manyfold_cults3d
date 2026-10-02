# frozen_string_literal: true

require "minitest/autorun"

class Cults3DCreatorServicesTest < Minitest::Test
  Source = ManyfoldCults3d::CreatorSource
  Deserializer = ManyfoldCults3d::CreatorDeserializer
  Client = ManyfoldCults3d::ApiClient
  PROFILE_URL = "https://cults3d.com/en/users/Example%20Studio"

  def setup
    @original_environment = %w[CULTS3D_USERNAME CULTS3D_API_KEY].to_h { |key| [key, ENV[key]] }
    ENV["CULTS3D_USERNAME"] = "fictional-creator-api-user"
    ENV["CULTS3D_API_KEY"] = "fictional-creator-api-key"
  end

  def teardown
    @original_environment.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  def test_profile_urls_and_localized_model_lists_share_a_canonical_profile
    paths = ["en/users", "de/benutzer", "es/usuarios", "fr/utilisateurs", "ru/polzovateli",
      "zh/y%C3%B2ngh%C3%B9", "en-gb/users"]
    paths.each do |path|
      ["", "/", "/3d-models", "/3d-models/"].each do |suffix|
        ["http://www.cults3d.com", "https://cults3d.com"].each do |origin|
          source = Source.new("#{origin}/#{path}/Example%20Studio#{suffix}?page=2#profile")
          assert_equal "Example Studio", source.username
          assert_equal PROFILE_URL, source.uri
        end
      end
    end
    assert_equal "https://cults3d.com/en/users/Example_Studio",
      Source.new("https://cults3d.com/de/benutzer/Example_Studio/3d-modelle").uri
  end

  def test_profile_parser_rejects_foreign_or_ambiguous_urls
    [nil, "", "Example Studio", "https://cults3d.com.evil.invalid/en/users/studio",
      "https://example.invalid/en/users/studio", "ftp://cults3d.com/en/users/studio",
      "https://user:password@cults3d.com/en/users/studio", "https://cults3d.com:80/en/users/studio",
      "http://cults3d.com:443/en/users/studio", "https://cults3d.com:444/en/users/studio",
      "https://cults3d.com/en/3d-model/art/studio", "https://cults3d.com/users/studio",
      "https://cults3d.com/en/users/studio/collections", "https://cults3d.com/en/users/a%2Fb",
      "https://cults3d.com/en/users/studio%00", "https://cults3d.com/en/users/%FF",
      "https://cults3d.com/en/users/..", "https://cults3d.com/en/users/%20studio"].each do |url|
      assert_raises(Source::Invalid) { Source.new(url) }
    end
  end

  def test_api_profile_must_match_the_returned_nickname
    assert_equal PROFILE_URL, Source.from_payload(creator_payload).uri
    assert_equal "Example Studio", Source.from_payload(creator_payload.merge(
      "url" => "https://cults3d.com/fr/utilisateurs/example%20studio/3d-models")).username
    [nil, {}, {"nick" => "Example Studio"}, creator_payload.merge("nick" => "Other Studio"),
      creator_payload.merge("url" => "https://example.invalid/en/users/Example%20Studio"),
      creator_payload.merge("nick" => " "), creator_payload.merge("nick" => ["Example Studio"])].each do |payload|
      assert_raises(Source::Invalid) { Source.from_payload(payload) }
    end
    assert Source.new(PROFILE_URL).matches?(creator_payload)
    refute Source.new(PROFILE_URL).matches?(creator_payload.merge("nick" => "Other Studio"))
  end

  def test_existing_creator_profiles_are_detected_without_counting_model_links
    creator = Struct.new(:links).new([Struct.new(:url).new("https://cults3d.com/en/3d-model/art/example")])
    refute Source.linked?(creator)
    creator.links << Struct.new(:url).new("http://www.cults3d.com/de/benutzer/Example%20Studio/3d-models/?page=2")
    assert Source.linked?(creator)
    creator.links = [Struct.new(:url).new("https://cults3d.com.evil.invalid/en/users/studio")]
    refute Source.linked?(creator)
  end

  def test_cached_api_profile_maps_native_creator_sync_attributes_without_another_request
    with_client(Object.new) do
      deserializer = Deserializer.new(uri: PROFILE_URL, payload: creator_payload)
      assert deserializer.valid?
      assert deserializer.valid?(for_class: ::Creator)
      refute deserializer.valid?(for_class: ::Model)
      assert_equal PROFILE_URL, deserializer.uri
      assert_equal({name: "Example Studio", slug: "example-studio", notes: "A fictional studio.",
        links_attributes: [{url: PROFILE_URL}], avatar_remote_url: "https://cdn.example.invalid/studio.png"},
        deserializer.deserialize)
      assert_equal ::Creator, deserializer.capabilities[:class]
    end
  end

  def test_sparse_and_unsafe_profile_metadata_is_omitted
    ["http://cdn.example.invalid/avatar.png", "https://user:password@cdn.example.invalid/avatar.png",
      "https://cdn.example.invalid:444/avatar.png", "not a URL", nil, ["https://example.invalid/avatar.png"]].each do |avatar|
      attributes = Deserializer.new(uri: PROFILE_URL, payload: creator_payload.merge(
        "bio" => nil, "imageUrl" => avatar)).deserialize
      refute attributes.key?(:notes)
      refute attributes.key?(:avatar_remote_url)
      assert_equal "Example Studio", attributes[:name]
    end
    assert_equal "", Deserializer.new(uri: PROFILE_URL, payload: creator_payload.merge("bio" => "")).deserialize[:notes]
  end

  def test_invalid_uris_are_safe_when_the_native_factory_constructs_deserializers
    [nil, "", "https://example.invalid/en/users/studio", "https://cults3d.com/en/3d-model/art/example"].each do |url|
      deserializer = Deserializer.new(uri: url, payload: creator_payload)
      refute deserializer.valid?
      assert_nil deserializer.uri
      assert_equal({}, deserializer.deserialize)
    end
  end

  def test_a_cached_profile_for_another_creator_cannot_be_synchronized
    deserializer = Deserializer.new(uri: PROFILE_URL, payload: creator_payload.merge("nick" => "Other Studio"))
    assert_raises(Client::InvalidResponse) { deserializer.deserialize }
  end

  def test_standalone_resync_fetches_the_profile_by_decoded_username
    client = Struct.new(:calls) do
      def creator(nick)
        calls << nick
        {"nick" => nick, "url" => "https://cults3d.com/en/users/Example%20Studio", "bio" => "Updated bio"}
      end
    end.new([])
    with_client(client) do
      assert_equal "Updated bio", Deserializer.new(uri: PROFILE_URL).deserialize[:notes]
      assert_equal ["Example Studio"], client.calls
    end
  end

  def test_api_failures_are_reported_in_the_native_link_sync_error_format
    client = Object.new
    client.define_singleton_method(:creator) { |_nick| raise Client::Unavailable, "Cults3D could not be reached." }
    with_client(client) do
      error = assert_raises(Faraday::Error) { Deserializer.new(uri: PROFILE_URL).deserialize }
      assert_equal "Cults3D could not be reached.", error.message
      assert_nil error.cause
    end
  end

  def test_a_mismatched_standalone_profile_reports_a_native_link_sync_error
    client = Object.new
    payload = creator_payload.merge("nick" => "Other Studio")
    client.define_singleton_method(:creator) { |_nick| payload }
    with_client(client) do
      error = assert_raises(Faraday::Error) { Deserializer.new(uri: PROFILE_URL).deserialize }
      assert_equal "Cults3D returned an unexpected creator profile.", error.message
      assert_nil error.cause
    end
  end

  def test_plugin_factory_is_idempotent_and_uses_environment_credentials
    ManyfoldCults3d::CreatorLinks.install!
    ManyfoldCults3d::CreatorLinks.install!
    assert_equal 1, ::Link.singleton_class.ancestors.count(ManyfoldCults3d::CreatorLinks::DeserializerFactory)
    assert_kind_of Deserializer, ::Link.deserializer_for(url: PROFILE_URL, for_class: ::Creator)
    assert_kind_of Deserializer, ::Link.deserializer_for(url: PROFILE_URL)
  end

  def test_factory_preserves_other_provider_and_model_deserializers
    fallback = Class.new do
      def self.deserializer_for(url:, for_class: nil)
        [url, for_class]
      end
    end
    fallback.singleton_class.prepend(ManyfoldCults3d::CreatorLinks::DeserializerFactory)
    model_url = "https://cults3d.com/en/3d-model/art/example"
    assert_equal [model_url, ::Model], fallback.deserializer_for(url: model_url, for_class: ::Model)
    other_url = "https://example.invalid/studio"
    assert_equal [other_url, ::Creator], fallback.deserializer_for(url: other_url, for_class: ::Creator)
    assert_equal [PROFILE_URL, ::Model], fallback.deserializer_for(url: PROFILE_URL, for_class: ::Model)
  end

  def test_unconfigured_plugin_deserializer_falls_through_without_network_requests
    singleton = Client.singleton_class
    original = Client.method(:configured?)
    singleton.send(:define_method, :configured?) { false }
    refute Deserializer.new(uri: PROFILE_URL, payload: creator_payload).valid?
    fallback = Class.new { def self.deserializer_for(**arguments); :native; end }
    fallback.singleton_class.prepend(ManyfoldCults3d::CreatorLinks::DeserializerFactory)
    assert_equal :native, fallback.deserializer_for(url: PROFILE_URL, for_class: ::Creator)
  ensure
    singleton.send(:define_method, :configured?, original) if original
  end

  private

  def creator_payload
    {"nick" => "Example Studio", "bio" => " A fictional studio. ", "url" => PROFILE_URL,
     "imageUrl" => "https://cdn.example.invalid/studio.png"}
  end

  def with_client(client)
    singleton = Client.singleton_class
    original = Client.method(:new)
    own_constructor = singleton.instance_methods(false).include?(:new)
    singleton.send(:define_method, :new) { |*arguments, **options, &block| client }
    yield
  ensure
    own_constructor ? singleton.send(:define_method, :new, original) : singleton.send(:remove_method, :new)
  end
end
