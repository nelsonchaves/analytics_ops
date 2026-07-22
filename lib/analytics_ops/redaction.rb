# frozen_string_literal: true

require "json"

module AnalyticsOps
  # Removes credential-shaped material before text reaches user-visible output.
  module Redaction
    BEARER = /\bBearer\s+[^\s,;]+/i
    AUTHORIZATION = /\bAuthorization\s*[:=]\s*[^\r\n,;]+/i
    PRIVATE_KEY = /-----BEGIN[^-]*PRIVATE KEY-----.*?-----END[^-]*PRIVATE KEY-----/mi
    SECRET_ASSIGNMENT = /
      (
        access[_ -]?token|refresh[_ -]?token|client[_ -]?(?:id|secret)|
        private[_ -]?key|password|api[_ -]?key|credentials?
      )
      \s*([:=]\s*|=>\s*)["']?[^\s,"';}]+
    /ix
    CONTROL_CHARACTERS = /[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/

    module_function

    def message(value)
      value.to_s
           .gsub(PRIVATE_KEY, "[REDACTED]")
           .gsub(AUTHORIZATION, "Authorization: [REDACTED]")
           .gsub(BEARER, "Bearer [REDACTED]")
           .gsub(SECRET_ASSIGNMENT) { "#{Regexp.last_match(1)}=[REDACTED]" }
           .gsub(CONTROL_CHARACTERS, "?")
           .slice(0, 1_000)
    end
  end

  # Writes small structured operational events without requests, responses, or credentials.
  module SafeLogging
    module_function

    def write(logger, level, event, details = {})
      return unless logger.respond_to?(level)

      payload = { "source" => "analytics_ops", "event" => event }.merge(details)
      logger.public_send(level, Redaction.message(JSON.generate(payload)))
    rescue StandardError
      nil
    end
  end
end
