# frozen_string_literal: true

module ::DiscourseEventDuplicator
  # Serves the standard Discourse SPA shell for the plugin's Ember-only
  # pages, so a full page load or refresh on /event-duplicator/new or
  # /event-duplicator/review (as opposed to an in-app client-side
  # transition) doesn't 404 -- Ember boots from the shell and takes over
  # client-side routing from there. Same pattern discourse-calendar uses for
  # its /upcoming-events page.
  class PagesController < ApplicationController
    def new
      raise ::ApplicationController::RenderEmpty
    end

    def review
      raise ::ApplicationController::RenderEmpty
    end
  end
end
