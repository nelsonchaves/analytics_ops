# frozen_string_literal: true

require_relative "analytics_ops/version"
require_relative "analytics_ops/errors"
require_relative "analytics_ops/redaction"
require_relative "analytics_ops/canonical"
require_relative "analytics_ops/resources"
require_relative "analytics_ops/desired_state"
require_relative "analytics_ops/configuration"
require_relative "analytics_ops/snapshot"
require_relative "analytics_ops/plan"
require_relative "analytics_ops/planner"
require_relative "analytics_ops/clients/error_translation"
require_relative "analytics_ops/clients/admin"
require_relative "analytics_ops/reports"
require_relative "analytics_ops/clients/data"
require_relative "analytics_ops/connection"
require_relative "analytics_ops/setup"
require_relative "analytics_ops/applier"
require_relative "analytics_ops/workspace"

# Safe Google Analytics 4 configuration and reporting operations.
module AnalyticsOps
end
