# frozen_string_literal: true

# Immutable configuration document.

module AnalyticsOps
  module Configuration
    # Immutable collection of validated named profiles.
    class Document
      attr_reader :version, :profiles

      def initialize(version:, profiles:)
        @version = version
        @profiles = Canonical.deep_freeze(profiles)
        freeze
      end

      def profile(name)
        profiles.fetch(name.to_s) do
          available = profiles.keys.sort.join(", ")
          raise ConfigurationError, "Unknown profile #{name.inspect}; available profiles: #{available}"
        end
      end
    end
  end
end
