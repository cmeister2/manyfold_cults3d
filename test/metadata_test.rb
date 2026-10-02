# frozen_string_literal: true

require "minitest/autorun"

class Cults3DMetadataTest < Minitest::Test
  Mapper = ManyfoldCults3d::MetadataMapper

  def test_raw_graphql_metadata_keeps_markdown_and_printing_settings
    attributes = Mapper.new({"name" => " Example sculpture ", "description" => "A **fictional** sculpture.",
      "details" => "Print at 0.2 mm.", "tags" => [" example ", "example", "sculpture"],
      "license" => {"spdxId" => "LicenseRef-Cults-PU"}, "safe" => false}).attributes
    assert_equal "Example sculpture", attributes[:name]
    assert_equal "A **fictional** sculpture.\n\n## Printing settings\n\nPrint at 0.2 mm.", attributes[:notes]
    assert_equal %w[example sculpture], attributes[:tag_list]
    assert_equal "LicenseRef-Cults-PU", attributes[:license]
    assert_equal true, attributes[:sensitive]
    assert_equal false, Mapper.new({"safe" => true}).attributes[:sensitive]
  end

  def test_cults_creator_fields_are_normalized_without_untrusted_profile_links
    designer = Mapper.new({"creator" => {"nick" => "example studio", "bio" => "Studio bio",
      "url" => "https://www.cults3d.com/en/users/example%20studio/?ref=example#part",
      "imageUrl" => "https://cdn.example.invalid/avatar.png"}}).designer
    assert_equal "example studio", designer["name"]
    assert_equal "https://cults3d.com/en/users/example%20studio", designer["profile_url"]
    assert_equal "https://cdn.example.invalid/avatar.png", designer["avatar_url"]
    fallback = Mapper.new({"creator" => {"nick" => "studio", "url" => "https://example.invalid/users/studio"}}).designer
    assert_equal "https://cults3d.com/en/users/studio", fallback["profile_url"]
  end

  def test_original_images_preserve_primary_identity_after_ordering_and_filename_collisions
    primary = "https://cdn.example.invalid/second/front%20view.jpg"
    mapper = Mapper.new({"illustrationImageUrl" => primary, "illustrations" => [
      {"id" => "second", "imageUrl" => primary, "position" => 2},
      {"id" => "first", "imageUrl" => "https://cdn.example.invalid/first/front_view.jpg", "position" => 1},
      {"imageUrl" => primary, "position" => 3}, {"imageUrl" => "http://cdn.example.invalid/unsafe.jpg"},
      {"imageUrl" => "https://user:password@cdn.example.invalid/unsafe.jpg"}, nil],
      "blueprints" => [{"fileUrl" => "https://cdn.example.invalid/model.stl"}],
      "downloadUrl" => "https://cults3d.com/en/downloads/1"})
    assert_equal %w[front_view.jpg front_view_2.jpg], mapper.file_urls.map { |file| file[:filename] }
    image = mapper.images.find { |candidate| candidate[:primary] }
    assert_equal "second", image[:id]
    assert_equal "front_view_2.jpg", image[:filename]
    assert_equal primary, image[:url]
  end

  def test_transformed_cults_images_use_the_original_asset
    original = "https://fbi.cults3d.com/upload/example.jpg"
    transformed = "https://images.cults3d.com/signature/516x516/filters:no_upscale()/#{original}"
    mapper = Mapper.new({"illustrationImageUrl" => transformed,
      "illustrations" => [{"imageUrl" => transformed, "position" => 1}]})
    assert_equal [{url: original, filename: "example.jpg"}], mapper.file_urls
    assert mapper.images.first[:primary]
  end

  def test_sparse_or_invalid_metadata_does_not_overwrite_existing_fields
    assert_equal({}, Mapper.new({}).attributes)
    assert_empty Mapper.new({}).images
    assert_nil Mapper.new({}).designer
    assert_equal({notes: "**HTML**"}, Mapper.new({"description" => "<p><strong>HTML</strong></p>"}).attributes)
    assert_nil Mapper.new({"license" => {"spdxId" => "MIT OR Apache-2.0"}}).attributes[:license]
  end
end
