# frozen_string_literal: true

module ::DiscourseEventDuplicator
  class Engine < ::Rails::Engine
    engine_name DiscourseEventDuplicator::PLUGIN_NAME
    isolate_namespace DiscourseEventDuplicator
    config.autoload_paths << File.join(config.root, "lib")
  end
end
