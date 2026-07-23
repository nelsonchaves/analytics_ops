# frozen_string_literal: true

module AnalyticsOps
  # Configuration-free Google connection used by discovery and setup.
  class Connection
    PROPERTY_ID = /\A\d{1,50}\z/

    # Immutable proof that both APIs can read the selected property.
    class Verification
      attr_reader :property

      def initialize(property:)
        unless property.is_a?(Resources::Property)
          raise ArgumentError, "property must be an AnalyticsOps::Resources::Property"
        end

        @property = property
        freeze
      end

      def to_h
        { "property" => property.to_h, "admin_api" => true, "data_api" => true }
      end
    end

    def initialize(admin: nil, data: nil, service_account: nil, transport: :grpc, timeout: nil, logger: nil)
      unless service_account.nil? || service_account.is_a?(ServiceAccount)
        raise ConfigurationError, "service_account must be an AnalyticsOps::ServiceAccount"
      end

      @admin = admin
      @data = data
      @service_account = service_account
      @transport = transport
      @timeout = timeout
      @logger = logger
    end

    def discover
      admin.discover
    end

    def properties
      admin.discover(include_streams: false)
    end

    def verify(property_id)
      unless property_id.is_a?(String) && PROPERTY_ID.match?(property_id)
        raise ConfigurationError, "Invalid property ID; expected a numeric string"
      end

      property = admin.property_access(property_id)
      data.run(property.id, connectivity_definition)
      Verification.new(property:)
    end

    private

    def admin
      @admin ||= Clients::Admin.new(
        service_account:,
        access: :read,
        transport: @transport,
        timeout: @timeout,
        logger: @logger
      )
    end

    def data
      @data ||= Clients::Data.new(
        service_account:,
        transport: @transport,
        timeout: @timeout,
        logger: @logger
      )
    end

    def service_account
      @service_account ||= ServiceAccount.load
    end

    def connectivity_definition
      @connectivity_definition ||= Reports::Definition.new(
        name: "setup_connectivity",
        kind: "standard",
        dimensions: ["date"],
        metrics: ["activeUsers"],
        date_ranges: [{ "start_date" => "today", "end_date" => "today" }],
        limit: 1
      )
    end
  end
end
