# frozen_string_literal: true

# Safe configuration entry point.

require_relative "configuration/document"
require_relative "configuration/loader"
require_relative "configuration/validator"
require_relative "configuration/schema"

module AnalyticsOps
  # Strict versioned desired-state loading.
  module Configuration
    module_function

    def load(path, environment: ENV)
      Loader.new(environment:).load(path)
    end
  end
end
