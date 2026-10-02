# frozen_string_literal: true

class Cults3DPluginTest
  def test_refresh_rolls_back_all_upserts_when_a_database_write_fails
    configure_api
    save_status_examples([model_entry(91001)])
    rows_before = library_models.order(:id).map(&:attributes)
    imported_at = SiteSettings.manyfold_cults3d_imported_at
    session = browser(@users.first)
    form = import_form(session)
    original_update = library_models.instance_method(:update!)
    failing_identifier = creation_identifier(91003)
    library_models.send(:define_method, :update!) do |attributes|
      if attributes[:cults3d_id] == failing_identifier
        errors.add(:name, "fictional database failure")
        raise ActiveRecord::RecordInvalid, self
      end
      original_update.bind_call(self, attributes)
    end
    client = FakeLibraryClient.new([model_entry(91002), model_entry(91003)])
    with_api_client(client) { post_refresh(session, form) }
    assert_equal 422, session.response.status
    assert_equal rows_before, library_models.order(:id).map(&:attributes)
    assert_equal imported_at, SiteSettings.manyfold_cults3d_imported_at
  ensure
    library_models.send(:remove_method, :update!) if original_update
  end
end
