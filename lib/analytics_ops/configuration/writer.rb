# frozen_string_literal: true

require "fileutils"
require "json"
require "securerandom"

module AnalyticsOps
  module Configuration
    # Safely creates the smallest valid configuration after interactive setup.
    class Writer
      # Immutable description of a configuration write or no-op.
      class Result
        attr_reader :path

        def initialize(path:, created:)
          raise ArgumentError, "created must be true or false" unless [true, false].include?(created)

          @path = path.to_s.dup.freeze
          @created = created
          freeze
        end

        def created?
          @created
        end

        def to_h
          { "path" => path, "created" => created? }
        end
      end

      def write_minimal(path, profile:, property_id:)
        state = validated_state(profile, property_id)
        expanded = File.expand_path(path)
        return existing_result(expanded, state) if File.exist?(expanded)

        FileUtils.mkdir_p(File.dirname(expanded))
        temporary = temporary_path(expanded)
        File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, 0o644) do |file|
          file.write(document(state))
          file.flush
          file.fsync
        end
        begin
          File.link(temporary, expanded)
        rescue Errno::EEXIST
          raise ConfigurationError, "Configuration #{Redaction.message(path)} was created by another process"
        end
        Result.new(path: expanded, created: true)
      rescue AnalyticsOps::Error
        raise
      rescue SystemCallError => error
        raise ConfigurationError,
              "Cannot write configuration #{Redaction.message(path)}: #{Redaction.message(error.message)}"
      ensure
        File.unlink(temporary) if temporary && File.exist?(temporary)
      end

      private

      def validated_state(profile, property_id)
        unless property_id.is_a?(String)
          raise ConfigurationError, "property_id must be a numeric identifier encoded as a string"
        end

        Validator.new(
          "version" => 1,
          "profiles" => { profile.to_s => { "property_id" => property_id } }
        ).call.profile(profile)
      end

      def existing_result(path, state)
        configuration = Configuration.load(path)
        unless configuration.profiles.key?(state.profile)
          raise ConfigurationError,
                "Configuration #{Redaction.message(path)} already exists without profile " \
                "#{state.profile.inspect}; setup will not rewrite it"
        end

        existing = configuration.profile(state.profile)
        unless existing.property_id == state.property_id
          raise ConfigurationError,
                "Profile #{state.profile.inspect} already targets property #{existing.property_id}; " \
                "setup will not overwrite it"
        end

        Result.new(path:, created: false)
      end

      def document(state)
        <<~YAML
          version: 1

          profiles:
            #{state.profile}:
              property_id: #{JSON.generate(state.property_id)}
        YAML
      end

      def temporary_path(path)
        File.join(File.dirname(path), ".#{File.basename(path)}.#{Process.pid}.#{SecureRandom.hex(6)}.tmp")
      end
    end
  end
end
