# frozen_string_literal: true

module AnalyticsOps
  class Error < StandardError; end
  class ConfigurationError < Error; end
  class AuthenticationError < Error; end
  class AuthorizationError < Error; end
  class UnsupportedCapabilityError < Error; end
  class StalePlanError < Error; end
end
