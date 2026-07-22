# frozen_string_literal: true

# Safe YAML loading implementation.

require "psych"

module AnalyticsOps
  module Configuration
    # Bounded safe-YAML reader with allowlisted environment interpolation.
    class Loader
      MAX_BYTES = 1_048_576
      VARIABLE = /\$\{([A-Z][A-Z0-9_]*)\}/

      def initialize(environment: ENV)
        @environment = environment
      end

      def load(path)
        source = read(path)
        raise ConfigurationError, "ERB is not allowed in Analytics Ops configuration" if source.include?("<%")

        parsed = Psych.safe_load(
          source,
          permitted_classes: [],
          permitted_symbols: [],
          aliases: false,
          filename: path.to_s,
          fallback: {}
        )

        Validator.new(interpolate(parsed)).call
      rescue Psych::Exception => error
        raise ConfigurationError, "Invalid YAML in #{path}: #{error.message}"
      end

      private

      def read(path)
        contents = File.binread(path, MAX_BYTES + 1)
        raise ConfigurationError, "Configuration exceeds #{MAX_BYTES} bytes" if contents.bytesize > MAX_BYTES

        contents
      rescue SystemCallError => error
        raise ConfigurationError, "Cannot read configuration #{path}: #{error.message}"
      end

      def interpolate(value)
        case value
        when Hash
          value.to_h { |key, child| [key, interpolate(child)] }
        when Array
          value.map { |child| interpolate(child) }
        when String
          interpolate_string(value)
        else
          value
        end
      end

      def interpolate_string(value)
        result = value.gsub(VARIABLE) do
          name = Regexp.last_match(1)
          raise EnvironmentVariableError, "Missing environment variable #{name}" unless @environment.key?(name)

          @environment.fetch(name).to_s
        end

        if result.include?("${")
          raise EnvironmentVariableError, "Malformed environment interpolation in #{value.inspect}"
        end

        result
      end
    end
  end
end
