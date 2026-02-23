# frozen_string_literal: true

module RailsDbInspector
  class ApplicationController < ActionController::Base
    protect_from_forgery with: :exception

    before_action :ensure_enabled!

    private

    def ensure_enabled!
      head :not_found unless RailsDbInspector.configuration.enabled
    end
  end
end
