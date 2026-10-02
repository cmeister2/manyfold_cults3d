# frozen_string_literal: true

require "minitest/autorun"
require "base64"

class Cults3DInventoryTest < Minitest::Test
  Inventory = ManyfoldCults3d::Inventory

  def test_nested_orders_normalize_creation_identity_and_safe_model_urls
    entry = order(42)
    creation = entry["lines"].first["creation"]
    creation["identifier"] = Base64.strict_encode64("Creation/42")
    creation["url"] = "https://www.cults3d.com/en/3d-model/art/copper-dragon-42/?utm_source=example#photos"
    creation["tags"] = [" miniature ", "dragon", "miniature"]
    original = Marshal.dump(entry)
    records = Inventory.attributes([entry])
    assert_equal 1, records.length
    record = records.first
    assert_equal identifier(42), record[:cults3d_id]
    assert_equal "copper-dragon-42", record[:slug]
    assert_equal "https://cults3d.com/en/3d-model/art/copper-dragon-42", record[:url]
    assert_equal "Copper Dragon 42", record[:name]
    assert_equal %w[miniature dragon], record[:tags]
    assert_equal ["ORDER"], record[:sources]
    assert_equal "example-studio", record[:creator_username]
    assert_equal "example-studio", record[:creator_name]
    assert_equal Time.utc(2024, 1, 1, 12), record[:published_at]
    assert_equal Time.utc(2025, 1, 1, 12), record[:library_added_at]
    assert_equal [{"order_id" => "Order/42", "line_id" => "Line/42",
                   "library_added_at" => "2025-01-01T12:00:00Z",
                   "download_url" => "https://cults3d.com/en/downloads/42?creation=copper-dragon-42"}], record[:library_entries]
    assert_equal original, Marshal.dump(entry)
  end

  def test_all_order_lines_are_listed_and_repeated_creations_deduplicate
    first = order(42)
    first["lines"] << order(43)["lines"].first
    second = order(42, order_id: "Order/99", line_id: "Line/99", added_at: "2025-02-01T13:00:00+01:00")
    second["lines"].first["creation"].merge!("name" => "Updated Copper Dragon", "tags" => ["updated", "dragon"])
    records = Inventory.attributes([second, first, first])
    assert_equal [identifier(42), identifier(43)], records.map { |record| record[:cults3d_id] }
    record = records.first
    assert_equal "Updated Copper Dragon", record[:name]
    assert_equal Time.utc(2025, 2, 1, 12), record[:library_added_at]
    assert_equal %w[updated dragon miniature], record[:tags]
    assert_equal ["Order/99", "Order/42"], record[:library_entries].map { |line| line["order_id"] }
    assert_equal 2, record[:library_entries].length
  end

  def test_newest_dated_order_wins_over_an_undated_order
    undated = order(42, added_at: nil)
    undated["lines"].first["creation"]["name"] = "Undated Dragon"
    dated = order(42, added_at: "2025-02-01T12:00:00Z")
    [[undated, dated], [dated, undated]].each do |orders|
      record = Inventory.attributes(orders).first
      assert_equal "Copper Dragon 42", record[:name]
      assert_equal Time.utc(2025, 2, 1, 12), record[:library_added_at]
      assert_equal 2, record[:library_entries].length
    end
  end

  def test_empty_library_and_nullable_optional_metadata_are_supported
    assert_empty Inventory.attributes([])
    entry = order(42, added_at: nil)
    creation = entry["lines"].first["creation"]
    creation.merge!("publishedAt" => nil, "creator" => nil, "tags" => [])
    entry["lines"].first["downloadUrl"] = nil
    record = Inventory.attributes([entry]).first
    assert_nil record[:creator_username]
    assert_nil record[:creator_avatar]
    assert_nil record[:published_at]
    assert_nil record[:library_added_at]
    assert_empty record[:tags]
    assert_nil record[:library_entries].first["download_url"]
  end

  def test_invalid_nested_shapes_ids_tags_dates_and_names_are_rejected
    examples = [nil, {}, [nil], [{"id" => "Order/42", "lines" => nil}], [order(42).merge("id" => "")]]
    [
      ["identifier", "0"], ["identifier", "not-a-creation-id"], ["slug", "not a slug!"],
      ["name", "  "], ["name", "x" * 256], ["name", "bad\u0000name"],
      ["tags", nil], ["tags", [123]], ["tags", ["  "]], ["tags", Array.new(129, "tag")],
      ["creator", "studio"], ["publishedAt", "yesterday"]
    ].each do |key, value|
      entry = order(42)
      entry["lines"].first["creation"][key] = value
      examples << [entry]
    end
    examples << [order(42, added_at: "2025-01-01")]
    entry = order(42)
    entry["lines"].first["id"] = "Line\n42"
    examples << [entry]
    examples.each do |orders|
      error = assert_raises(Inventory::Error) { Inventory.attributes(orders) }
      assert_equal "Cults3D returned invalid library data. Your saved library has not changed.", error.message
    end
  end

  def test_model_urls_must_use_cults_https_and_match_the_returned_slug
    ["http://cults3d.com/en/3d-model/art/copper-dragon-42",
     "https://example.invalid/en/3d-model/art/copper-dragon-42",
     "https://cults3d.com.example.invalid/en/3d-model/art/copper-dragon-42",
     "https://user:password@cults3d.com/en/3d-model/art/copper-dragon-42",
     "https://cults3d.com:8443/en/3d-model/art/copper-dragon-42",
     "https://cults3d.com/en/3d-model/art/a-different-dragon"].each do |url|
      entry = order(42)
      entry["lines"].first["creation"]["url"] = url
      assert_raises(Inventory::Error) { Inventory.attributes([entry]) }
    end
  end

  def test_download_links_are_restricted_to_cults_https_download_pages
    ["http://cults3d.com/en/downloads/42", "https://example.invalid/en/downloads/42",
     "https://user:password@cults3d.com/en/downloads/42", "https://cults3d.com:8443/en/downloads/42",
     "https://cults3d.com/en/3d-model/art/copper-dragon-42", "https://cults3d.com/en/downloads/0"].each do |url|
      entry = order(42)
      entry["lines"].first["downloadUrl"] = url
      assert_raises(Inventory::Error) { Inventory.attributes([entry]) }
    end
  end

  def test_invalid_late_entry_has_no_database_writes_or_input_mutations
    valid = order(42)
    invalid = order(43)
    invalid["lines"].first["creation"]["tags"] = ["bad\nvalue"]
    orders = [valid, invalid]
    original = Marshal.dump(orders)
    writes = []
    callback = lambda do |_name, _start, _finish, _id, payload|
      writes << payload[:sql] if payload[:sql].match?(/\A\s*(?:INSERT|UPDATE|DELETE)\b/i)
    end
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      assert_raises(Inventory::Error) { Inventory.attributes(orders) }
    end
    assert_empty writes
    assert_equal original, Marshal.dump(orders)
  end

  private

  def identifier(id)
    Base64.strict_encode64("Creation/#{id}").delete("=")
  end

  def order(id, order_id: "Order/#{id}", line_id: "Line/#{id}", added_at: "2025-01-01T12:00:00Z")
    {"id" => order_id, "createdAt" => added_at, "lines" => [{"id" => line_id,
      "downloadUrl" => "https://cults3d.com/en/downloads/#{id}?creation=copper-dragon-#{id}",
      "creation" => {"identifier" => identifier(id), "slug" => "copper-dragon-#{id}",
        "name" => "Copper Dragon #{id}", "url" => "https://cults3d.com/en/3d-model/art/copper-dragon-#{id}",
        "publishedAt" => "2024-01-01T12:00:00Z", "tags" => %w[miniature dragon],
        "creator" => {"nick" => "example-studio", "imageUrl" => "https://fbi.cults3d.com/example/avatar.png"}}}]}
  end
end
