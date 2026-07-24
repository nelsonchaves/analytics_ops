# frozen_string_literal: true

module AnalyticsOps
  # Command-line consumer of the public Analytics Ops API.
  class CLI
    # Implements safe, interactive and non-interactive Google setup.
    module SetupCommands
      private

      def setup(connection, service_account, profile:)
        result = run_setup(connection, service_account, profile:)
        connection_name = remember_setup_connection(profile, service_account)
        return render_setup_result(result, connection_name) if human?

        render(result.to_h.merge("connection" => connection_name))
      end

      def run_setup(connection, service_account, profile:)
        Setup.new(
          connection:,
          config: @options.fetch(:config),
          profile:,
          property_id: @options[:property],
          noninteractive: @options[:noninteractive],
          warnings: service_account_warnings(service_account),
          input: @input,
          out: @out
        ).call
      end

      def remember_setup_connection(profile, service_account)
        connection_name = setup_connection_name(profile, service_account)
        service_account_store.write(
          service_account.path,
          name: connection_name,
          config: @options.fetch(:config),
          profile:
        )
        connection_name
      end

      def render_setup_result(result, connection_name)
        action = if result.created?
                   "Created"
                 elsif result.updated?
                   "Updated"
                 else
                   "Using"
                 end
        @out.puts "#{action} #{Redaction.message(result.config_path)}"
        @out.puts "Connected #{Redaction.message(result.profile)} to " \
                  "#{Redaction.message(result.property.display_name)} " \
                  "(property #{Redaction.message(result.property.id)})."
        @out.puts "Saved Google connection #{Redaction.message(connection_name)}."
        result.warnings.each { |warning| @err.puts "Warning: #{Redaction.message(warning)}" }
        @out.puts "Next: analytics-ops overview"
        SUCCESS
      end

      def setup_connection_name(profile, service_account)
        return @options.fetch(:connection) if @options[:connection]
        return new_connection_name(profile, service_account) if @options[:service_account]
        return profile unless service_account_store.respond_to?(:resolve_connection_name)

        service_account_store.resolve_connection_name(
          config: @options.fetch(:config),
          profile:
        )
      end

      def new_connection_name(profile, service_account)
        return profile unless service_account_store.respond_to?(:connection_name_for)

        service_account_store.connection_name_for(
          service_account.path,
          preferred: profile,
          config: @options.fetch(:config),
          profile:
        )
      end

      def service_account_warnings(service_account)
        return [] unless service_account.respond_to?(:security_warnings)

        service_account.security_warnings
      end
    end

    include SetupCommands
  end
end
