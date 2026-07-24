# frozen_string_literal: true

require "fileutils"
require "json"
require "securerandom"
require "tmpdir"

module AnalyticsOps
  module Configuration
    # Safely creates the smallest valid configuration after interactive setup.
    class Writer
      # Immutable description of a configuration write or no-op.
      class Result
        attr_reader :path

        def initialize(path:, created:, updated: false)
          unless [true, false].include?(created) && [true, false].include?(updated) && !(created && updated)
            raise ArgumentError, "created and updated must be distinct booleans"
          end

          @path = path.to_s.dup.freeze
          @created = created
          @updated = updated
          freeze
        end

        def created?
          @created
        end

        def updated?
          @updated
        end

        def changed?
          created? || updated?
        end

        def to_h
          { "path" => path, "created" => created?, "updated" => updated? }
        end
      end

      def write_minimal(path, profile:, property_id:)
        state = validated_state(profile, property_id)
        expanded = File.expand_path(path)
        return existing_result(File.realpath(expanded), state) if File.exist?(expanded)

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
        source = read_source(path)
        configuration = Configuration.load(path)
        unless configuration.profiles.key?(state.profile)
          updated = append_profile(source, state)
          atomic_replace(path, original: source, replacement: updated)
          return Result.new(path:, created: false, updated: true)
        end

        existing = configuration.profile(state.profile)
        unless existing.property_id == state.property_id
          raise ConfigurationError,
                "Profile #{state.profile.inspect} already targets property #{existing.property_id}; " \
                "setup will not overwrite it"
        end

        Result.new(path:, created: false)
      rescue EnvironmentVariableError
        replacement = replace_generator_placeholder(source, state)
        raise unless replacement

        atomic_replace(path, original: source, replacement:)
        Result.new(path:, created: false, updated: true)
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

      def read_source(path)
        source = File.binread(path, Loader::MAX_BYTES + 1)
        if source.bytesize > Loader::MAX_BYTES
          raise ConfigurationError, "Configuration exceeds #{Loader::MAX_BYTES} bytes"
        end

        source
      end

      def append_profile(source, state)
        profiles = profiles_mapping(source)
        indentation = " " * profiles.children.first.start_column
        snippet = "#{indentation}#{state.profile}:\n" \
                  "#{indentation}  property_id: #{JSON.generate(state.property_id)}\n"
        lines = source.lines
        index = profiles.end_line
        complete_final_line(lines, index)
        lines.insert(index, snippet)
        lines.join
      rescue Psych::Exception => error
        raise ConfigurationError, "Configuration cannot be updated safely: #{Redaction.message(error.message)}"
      end

      def profiles_mapping(source)
        root = Psych.parse(source)&.root
        raise ConfigurationError, "Configuration root must be a mapping" unless root.is_a?(Psych::Nodes::Mapping)

        profiles = root.children.each_slice(2).find do |key, _value|
          key.is_a?(Psych::Nodes::Scalar) && key.value == "profiles"
        end&.last
        unless profiles.is_a?(Psych::Nodes::Mapping) && profiles.children.any?
          raise ConfigurationError, "Configuration profiles mapping cannot be updated safely"
        end

        profiles
      end

      def complete_final_line(lines, insertion_index)
        return unless insertion_index == lines.length && lines.last && !lines.last.end_with?("\n")

        lines[-1] = "#{lines.last}\n"
      end

      def replace_generator_placeholder(source, state)
        placeholder = '"${GA4_PROPERTY_ID}"'
        return nil unless source.scan(placeholder).length == 1

        candidate = source.sub(placeholder, JSON.generate(state.property_id))
        temporary_document(candidate, state)
        candidate
      end

      def atomic_replace(path, original:, replacement:)
        temporary_document(replacement)
        temporary = temporary_path(path)
        mode = File.stat(path).mode & 0o777
        File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, mode) do |file|
          file.write(replacement)
          file.flush
          file.fsync
        end
        unless File.binread(path, Loader::MAX_BYTES + 1) == original
          raise ConfigurationError, "Configuration #{Redaction.message(path)} changed while setup was running"
        end

        File.rename(temporary, path)
        File.chmod(mode, path)
      ensure
        File.unlink(temporary) if temporary && File.exist?(temporary)
      end

      def temporary_document(source, expected_state = nil)
        temporary = File.join(Dir.tmpdir, "analytics-ops-config-#{Process.pid}-#{SecureRandom.hex(6)}.yml")
        File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, 0o600) { |file| file.write(source) }
        configuration = Configuration.load(temporary)
        if expected_state
          actual = configuration.profile(expected_state.profile)
          unless actual.property_id == expected_state.property_id
            raise ConfigurationError, "Generated configuration does not match the selected property"
          end
        end
        configuration
      ensure
        File.unlink(temporary) if temporary && File.exist?(temporary)
      end
    end
  end
end
