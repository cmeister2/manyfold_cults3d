# frozen_string_literal: true

module ManyfoldMyminifactory
  class StatusController < ::ApplicationController
    def index
      skip_policy_scope
      @linked = SiteSettings.myminifactory_api_key.present?
    end
  end
end
