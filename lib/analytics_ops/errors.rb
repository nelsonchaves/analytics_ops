# frozen_string_literal: true

# Public typed errors.

require_relative "redaction"

module AnalyticsOps
  # Base for every expected, safely reportable Analytics Ops failure.
  class Error < StandardError
    attr_reader :remote_reason, :remote_metadata, :remote_code

    def initialize(message = nil, remote_reason: nil, remote_metadata: nil, remote_code: nil)
      @remote_reason = safe_remote_value(remote_reason, 128)
      @remote_metadata = safe_remote_metadata(remote_metadata)
      @remote_code = safe_remote_value(remote_code, 64)
      super(message)
    end

    private

    def safe_remote_value(value, limit)
      return nil if value.nil?

      Redaction.message(value).slice(0, limit).freeze
    end

    def safe_remote_metadata(value)
      return {}.freeze if value.nil?
      return {}.freeze unless value.respond_to?(:to_h)

      value.to_h.first(32).to_h do |key, child|
        [safe_remote_value(key, 128), safe_remote_value(child, 256)]
      end.freeze
    rescue StandardError
      {}.freeze
    end
  end

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
