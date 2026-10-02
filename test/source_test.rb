# frozen_string_literal: true

require "minitest/autorun"
require "base64"
require_relative "../app/services/manyfold_cults3d/source"

class Cults3DSourceTest < Minitest::Test
  Source = ManyfoldCults3d::Source
  IDENTIFIER = Base64.strict_encode64("Creation/92001").delete("=")

  def test_numeric_and_global_identifiers_use_the_same_api_identifier
    ["92001", " 92001 ", IDENTIFIER, Base64.strict_encode64("Creation/92001"),
      "https://cults3d.com/:92001", "https://www.cults3d.com/:92001/?ref=example#part"].each do |value|
      source = Source.new(value)
      assert_equal IDENTIFIER, source.id, value
      assert_equal "92001", source.numeric_id, value
      assert_nil source.slug
    end
  end

  def test_model_urls_keep_the_slug_including_numeric_suffixes
    ["example-92001", "https://cults3d.com/en/3d-model/art/example-92001",
      "https://www.cults3d.com/fr/3d-model/art/example-92001/?ref=example#part"].each do |value|
      source = Source.new(value)
      assert_equal "example-92001", source.id
      assert_equal "example-92001", source.slug
      assert_nil source.identifier
    end
  end

  def test_encoded_unicode_slugs_are_decoded_without_accepting_path_separators
    assert_equal "caf\u00e9", Source.new("https://cults3d.com/en/3d-model/art/caf%C3%A9").slug
    assert_raises(Source::Invalid) { Source.new("https://cults3d.com/en/3d-model/art/other%2Fexample") }
  end

  def test_numeric_slugs_keep_the_url_when_queued_to_avoid_becoming_numeric_ids
    url = "https://cults3d.com/en/3d-model/art/123"
    source = Source.new(url)
    assert_equal "123", source.slug
    assert_equal url, source.id
    assert_equal "123", Source.new(source.id).slug
    assert_nil source.identifier
  end

  def test_invalid_sources_are_rejected
    [nil, "", "0", "01", "-1", "1.0", (Source::MAX_ID + 1).to_s, "9" * 100,
      "https://example.invalid/en/3d-model/art/example", "https://cults3d.com.example.invalid/:92001",
      "http://cults3d.com/:92001", "https://user:password@cults3d.com/:92001",
      "https://cults3d.com:444/:92001", "https://cults3d.com/en/users/example",
      "https://cults3d.com/en/3d-model/art/example/files", "../92001",
      Base64.strict_encode64("User/92001").delete("="), Base64.strict_encode64("Creation/0").delete("=")].each do |value|
      assert_raises(Source::Invalid, value.inspect) { Source.new(value) }
    end
  end

  def test_canonical_urls_are_checked_against_the_payload_identity
    payload = {"identifier" => IDENTIFIER, "slug" => "example", "shortUrl" => "https://cults3d.com/:92001",
      "url" => "https://www.cults3d.com/en/3d-model/art/example/?ref=example#part"}
    assert_equal "https://cults3d.com/en/3d-model/art/example", Source.canonical_url(payload)
    assert Source.new("92001").matches?(payload)
    assert Source.new("example").matches?(payload)
    refute Source.new("92002").matches?(payload)
    refute Source.new("different").matches?(payload)
    refute Source.new("example").matches?(payload.merge("identifier" => "User/92001"))
    refute Source.new("92001").matches?(payload.merge("identifier" => "92001"))
    assert_raises(Source::Invalid) { Source.canonical_url(payload.merge("slug" => "different")) }
    assert_raises(Source::Invalid) { Source.canonical_url(payload.merge("shortUrl" => "https://cults3d.com/:92002")) }
    assert_raises(Source::Invalid) { Source.canonical_url(payload.merge("url" => "https://example.invalid/example")) }
  end
end
