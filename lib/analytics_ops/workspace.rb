# frozen_string_literal: true

# Primary plain-Ruby API.

require "time"

module AnalyticsOps
  # Primary Ruby API. Loading a workspace validates local data but performs no network calls.
  class Workspace
    # Immutable convergence result returned by verify.
    class Verification
      attr_reader :converged, :plan

      def initialize(plan:)
        @plan = plan
        @converged = !plan.drift?
        freeze
      end

      def to_h
        { "converged" => converged, "plan" => plan.to_h }
      end
    end

    # Immutable health-check collection returned by doctor.
    class DoctorResult
      attr_reader :checks

      def initialize(checks:)
        @checks = Canonical.immutable(checks)
        freeze
      end

      def success?
        checks.none? { |check| check.fetch("status") == "error" }
      end

      def to_h
        { "success" => success?, "checks" => checks }
      end
    end

    attr_reader :desired_state

    def self.load(path, profile:, environment: ENV, admin: nil, data: nil, service_account: nil,
                  transport: :grpc, timeout: nil, logger: nil)
      document = Configuration.load(path, environment:)
      new(desired_state: document.profile(profile), admin:, data:, service_account:, transport:, timeout:, logger:)
    end

    def initialize(desired_state:, admin: nil, data: nil, service_account: nil,
                   transport: :grpc, timeout: nil, logger: nil)
      unless service_account.nil? || service_account.is_a?(ServiceAccount)
        raise ConfigurationError, "service_account must be an AnalyticsOps::ServiceAccount"
      end

      @desired_state = desired_state
      @admin = admin
      @injected_admin = admin
      @data = data
      @service_account = service_account
      @transport = transport
      @timeout = timeout
      @logger = logger
    end

    def discover
      admin.discover
    end

    def snapshot
      admin.snapshot(desired_state.property_id)
    end

    def audit
      plan
    end

    def plan
      Planner.new(desired_state:, snapshot:).call
    end

    def apply(plan_or_path, confirm: false)
      saved_plan = plan_or_path.is_a?(Plan) ? plan_or_path : Plan.load(plan_or_path)
      validate_plan_target!(saved_plan)
      Applier.new(admin: edit_admin).call(saved_plan, confirm:)
    end

    def verify
      Verification.new(plan:)
    end

    def report(name_or_definition)
      definition = report_definition(name_or_definition, kind: "standard")
      data.run(desired_state.property_id, definition)
    end

    def realtime(name_or_definition = "realtime_events")
      definition = report_definition(name_or_definition, kind: "realtime")
      data.run(desired_state.property_id, definition)
    end

    def overview
      reports = data.batch(desired_state.property_id, Reports::Catalog.overview)
      Reports::OverviewResult.new(property_id: desired_state.property_id, reports:)
    end

    def doctor
      remote = snapshot
      checks = [
        { "name" => "configuration", "status" => "ok", "detail" => "Profile #{desired_state.profile} is valid" },
        { "name" => "credentials", "status" => "ok",
          "detail" => "Google accepted the configured service-account credentials" },
        { "name" => "admin_api", "status" => "ok", "detail" => "Admin API read succeeded" },
        { "name" => "property_access", "status" => "ok", "detail" => "Read properties/#{remote.property_id}" }
      ]
      checks.concat(compatibility_checks)
      checks << clock_check
      checks << edit_capability_check
      data.run(desired_state.property_id, doctor_report_definition)
      checks << { "name" => "data_api", "status" => "ok", "detail" => "Data API read succeeded" }
      checks << {
        "name" => "credential_scope",
        "status" => "ok",
        "detail" => "This read-only command uses the Analytics read-only scope"
      }
      admin.capabilities.each do |name, available|
        checks << {
          "name" => name,
          "status" => available ? "ok" : "unsupported",
          "detail" => available ? "Installed client exposes this capability" : "Installed client lacks this capability"
        }
      end
      DoctorResult.new(checks:)
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

    def edit_admin
      return @injected_admin if @injected_admin

      @edit_admin ||= Clients::Admin.new(
        service_account:,
        access: :edit,
        transport: @transport,
        timeout: @timeout,
        logger: @logger
      )
    end

    def service_account
      @service_account ||= ServiceAccount.load
    end

    def compatibility_checks
      [admin.compatibility, data.compatibility].map do |details|
        {
          "name" => details.fetch("package"),
          "status" => details.fetch("supported") ? "ok" : "unsupported",
          "detail" => "Installed #{details.fetch("version")}; supported #{details.fetch("requirement")}; " \
                      "transport #{details.fetch("transport")}"
        }
      end
    end

    def clock_check
      now = Time.now.utc
      plausible = now.year.between?(2024, 2100)
      {
        "name" => "local_clock",
        "status" => plausible ? "ok" : "error",
        "detail" => plausible ? "Local UTC clock is plausible: #{now.iso8601}" : "Local UTC clock is implausible"
      }
    end

    def edit_capability_check
      access = admin.property_access(desired_state.property_id)
      case access.can_edit
      when true
        { "name" => "edit_capability", "status" => "ok", "detail" => "Account summary reports edit access" }
      when false
        { "name" => "edit_capability", "status" => "warning", "detail" => "Account summary reports read-only access" }
      else
        { "name" => "edit_capability", "status" => "unknown", "detail" => "Google did not report edit capability" }
      end
    end

    def doctor_report_definition
      Reports::Definition.new(
        name: "doctor_connectivity",
        kind: "standard",
        dimensions: ["eventName"],
        metrics: ["eventCount"],
        date_ranges: [{ "start_date" => "yesterday", "end_date" => "yesterday" }],
        limit: 1
      )
    end

    def report_definition(name_or_definition, kind:)
      definition = if name_or_definition.is_a?(Reports::Definition)
                     name_or_definition
                   else
                     Reports::Catalog.fetch(name_or_definition, kind:)
                   end
      unless definition.kind == kind
        raise InvalidRequestError, "Report #{definition.name} is #{definition.kind}, not #{kind}"
      end

      definition
    end

    def validate_plan_target!(saved_plan)
      unless saved_plan.profile == desired_state.profile
        raise InvalidPlanError,
              "Plan profile #{saved_plan.profile.inspect} does not match #{desired_state.profile.inspect}"
      end
      return if saved_plan.property_id == desired_state.property_id

      raise InvalidPlanError, "Plan property #{saved_plan.property_id} does not match configured property"
    end
  end
end
