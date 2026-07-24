# frozen_string_literal: true

module AnalyticsOps
  # Read-only summary across every profile in one Analytics Ops configuration.
  class Portfolio
    # One property/period row in a portfolio summary.
    class Entry < Resources::Value
      fields :profile, :property_id, :period, :active_users, :sessions, :key_events
    end

    # Immutable multi-property report result.
    class Result
      attr_reader :entries, :date_ranges

      def initialize(entries:, date_ranges:)
        unless entries.is_a?(Array) && entries.all?(Entry)
          raise ArgumentError, "entries must contain AnalyticsOps::Portfolio::Entry values"
        end
        raise ArgumentError, "date_ranges must be an array" unless date_ranges.is_a?(Array)

        @entries = entries.dup.freeze
        @date_ranges = Canonical.immutable(date_ranges)
        freeze
      end

      def to_h
        {
          "entries" => entries.map(&:to_h),
          "date_ranges" => date_ranges
        }
      end
    end

    def initialize(config:, store: ServiceAccount::Store.new, workspace_loader: nil,
                   service_account_loader: nil, transport: :grpc, timeout: nil, logger: nil)
      @config = config
      @store = store
      @workspace_loader = workspace_loader || method(:load_workspace)
      @service_account_loader = service_account_loader || ServiceAccount.method(:load)
      @transport = transport
      @timeout = timeout
      @logger = logger
    end

    def overview(date_ranges: nil)
      document = Configuration.load(@config)
      definition = Reports::Catalog.overview.first
      definition = definition.with_date_ranges(date_ranges) if date_ranges
      entries = document.profiles.sort.flat_map do |profile, desired_state|
        report = workspace(profile).report(definition)
        report_entries(profile, desired_state.property_id, report)
      end
      Result.new(entries:, date_ranges: definition.date_ranges)
    end

    private

    def workspace(profile)
      service_account = @service_account_loader.call(
        store: @store,
        connection: nil,
        config: @config,
        profile:
      )
      @workspace_loader.call(
        config: @config,
        profile:,
        service_account:,
        transport: @transport,
        timeout: @timeout,
        logger: @logger
      )
    end

    def load_workspace(config:, profile:, service_account:, transport:, timeout:, logger:)
      Workspace.load(config, profile:, service_account:, transport:, timeout:, logger:)
    end

    def report_entries(profile, property_id, report)
      unless report.is_a?(Reports::Result) &&
             report.metric_headers == %w[activeUsers sessions keyEvents] &&
             [[], ["dateRange"]].include?(report.dimension_headers)
        raise RemoteError, "Portfolio report returned an unexpected shape"
      end

      rows = report.rows
      rows = [{ "activeUsers" => "0", "sessions" => "0", "keyEvents" => "0" }] if rows.empty?
      rows.map do |row|
        Entry.new(
          profile:,
          property_id:,
          period: row.fetch("dateRange", "current"),
          active_users: row.fetch("activeUsers"),
          sessions: row.fetch("sessions"),
          key_events: row.fetch("keyEvents")
        )
      end
    end
  end
end
