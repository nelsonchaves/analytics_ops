# frozen_string_literal: true

# Public typed errors.

module AnalyticsOps
  class Error < StandardError; end
  class ConfigurationError < Error; end
  class EnvironmentVariableError < ConfigurationError; end
  class UnsupportedVersionError < ConfigurationError; end
  class AuthenticationError < Error; end
  class AuthorizationError < Error; end
  class UnsupportedCapabilityError < Error; end
  class ConflictError < Error; end
  class InvalidPlanError < Error; end
  class StalePlanError < Error; end
  class ConfirmationRequiredError < Error; end
  class QuotaError < Error; end
  class TimeoutError < Error; end
  class InvalidRequestError < Error; end
  class RemoteError < Error; end

  # Apply failure carrying structured successful, failed, and remaining changes.
  class PartialApplyError < Error
    attr_reader :result

    def initialize(message, result:)
      @result = result
      super(message)
    end
  end
end
