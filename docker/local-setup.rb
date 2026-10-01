# frozen_string_literal: true

admin = User.with_role(:administrator).first
unless admin
  admin = User.create!(username: "developer", email: "developer@example.invalid",
    password: SecureRandom.base64(32), approved: true)
  admin.add_role(:administrator)
end
admin.update!(reset_password_token: nil) if admin.first_use?

library = Library.first || Library.create!(name: "Local development", path: "/config/models",
  storage_service: "filesystem", path_template: "{creator}/{modelName}")
library.make_default if SiteSettings.default_library.nil?
