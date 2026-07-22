# frozen_string_literal: true

# Safe YAML loading implementation.

require "psych"

module AnalyticsOps
  module Configuration
    # Bounded safe-YAML reader with allowlisted environment interpolation.
    class Loader
      MAX_BYTES = 1_048_576
      MAX_NESTING = 50
      VARIABLE = /\$\{([A-Z][A-Z0-9_]*)\}/

      def initialize(environment: ENV)
        @environment = environment
      end

      def load(path)
        source = read(path)
        raise ConfigurationError, "ERB is not allowed in Analytics Ops configuration" if source.include?("<%")

        reject_duplicate_mapping_keys!(source)

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
        raise ConfigurationError,
              "Invalid YAML in #{Redaction.message(path)}: #{Redaction.message(error.message)}"
      end

      private

      def read(path)
        contents = File.binread(path, MAX_BYTES + 1)
        raise ConfigurationError, "Configuration exceeds #{MAX_BYTES} bytes" if contents.bytesize > MAX_BYTES

        contents
      rescue SystemCallError => error
        raise ConfigurationError,
              "Cannot read configuration #{Redaction.message(path)}: #{Redaction.message(error.message)}"
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

      def reject_duplicate_mapping_keys!(source)
        visit_yaml_node(Psych.parse_stream(source))
      end

      def visit_yaml_node(node, depth = 0)
        raise ConfigurationError, "Configuration YAML nesting exceeds #{MAX_NESTING}" if depth > MAX_NESTING

        if node.is_a?(Psych::Nodes::Mapping)
          visit_yaml_mapping(node, depth)
        elsif node.respond_to?(:children)
          Array(node.children).each { |child| visit_yaml_node(child, depth + 1) }
        end
      end

      def visit_yaml_mapping(node, depth)
        keys = {}
        node.children.each_slice(2) do |key, value|
          if key.is_a?(Psych::Nodes::Scalar)
            duplicate = keys.key?(key.value)
            keys[key.value] = true
            if duplicate
              label = Redaction.message(key.value.inspect)
              raise ConfigurationError, "Duplicate YAML mapping key #{label}"
            end
          end
          visit_yaml_node(key, depth + 1)
          visit_yaml_node(value, depth + 1)
        end
      end

      def interpolate_string(value)
        result = value.gsub(VARIABLE) do
          name = Regexp.last_match(1)
          raise EnvironmentVariableError, "Missing environment variable #{name}" unless @environment.key?(name)

          @environment.fetch(name).to_s
        end

        raise EnvironmentVariableError, "Malformed environment interpolation" if result.include?("${")

        result
      end
    end
  end
end
