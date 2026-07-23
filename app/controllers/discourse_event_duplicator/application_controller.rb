# frozen_string_literal: true

module ::DiscourseEventDuplicator
  class ApplicationController < ::ApplicationController
    requires_plugin DiscourseEventDuplicator::PLUGIN_NAME
  end
end
