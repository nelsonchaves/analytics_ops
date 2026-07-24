# frozen_string_literal: true

module AnalyticsOps
  # Command-line consumer of the public Analytics Ops API.
  class CLI
    # Implements local setup, selection, portfolio, and AI commands.
    module LocalCommands
      private

      def dispatch_local(command)
        case command
        when "connections"
          presenter.render_connections(service_account_store.summaries)
        when "profiles"
          render_profiles
        when "use"
          use_profile
        when "mcp"
          start_mcp
        end
      end

      def render_profiles
        config = @options.fetch(:config)
        document = Configuration.load(config)
        selected = service_account_store.selection(config:)
        selected_profile = selected&.fetch("profile") || @options.fetch(:profile)
        profiles = document.profiles.sort.map do |name, desired_state|
          {
            "name" => name,
            "property_id" => desired_state.property_id,
            "connection" => service_account_store.profile_connection(config:, profile: name),
            "selected" => selected_profile == name
          }
        end
        presenter.render_profiles(profiles)
      end

      def use_profile
        profile = required_use_profile!
        config = @options.fetch(:config)
        Configuration.load(config).profile(profile)
        selection = service_account_store.select(
          config:,
          profile:,
          connection: @options[:connection]
        )
        presenter.render_selection(selection)
      end

      def start_mcp
        @mcp_server_loader.call(
          config: @options.fetch(:config),
          profile: resolved_profile,
          connection: @options[:connection],
          store: service_account_store,
          workspace_loader: @workspace_loader,
          connection_loader: @connection_loader,
          service_account_loader: @service_account_loader,
          portfolio_loader: @portfolio_loader,
          transport: @options.fetch(:transport),
          timeout: @options[:timeout],
          logger: operation_logger
        ).start
        SUCCESS
      end

      def required_use_profile!
        raise OptionParser::MissingArgument, "use requires exactly one PROFILE" unless @arguments.length == 1

        profile = @arguments.first
        raise OptionParser::InvalidArgument, "use requires a valid profile name" unless Options::PROFILE.match?(profile)

        profile
      end
    end

    include LocalCommands
  end
end
