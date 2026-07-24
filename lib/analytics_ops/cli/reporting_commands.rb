# frozen_string_literal: true

module AnalyticsOps
  # Command-line consumer of the public Analytics Ops API.
  class CLI
    # Implements date-aware reporting and multi-property portfolio commands.
    module ReportingCommands
      private

      def run_portfolio
        portfolio = @portfolio_loader.call(
          config: @options.fetch(:config),
          store: service_account_store,
          workspace_loader: @workspace_loader,
          service_account_loader: @service_account_loader,
          transport: @options.fetch(:transport),
          timeout: @options[:timeout],
          logger: operation_logger
        )
        ranges = report_date_ranges
        result = ranges ? portfolio.overview(date_ranges: ranges) : portfolio.overview
        render(result)
      end

      def render_workspace_overview(workspace)
        ranges = report_date_ranges
        render(ranges ? workspace.overview(date_ranges: ranges) : workspace.overview)
      end

      def render_workspace_report(workspace)
        name = required_report_name!("report")
        ranges = report_date_ranges
        render(ranges ? workspace.report(name, date_ranges: ranges) : workspace.report(name))
      end

      def report_date_ranges
        Reports::Period.resolve(
          last_days: @options[:last_days],
          start_date: @options[:start_date],
          end_date: @options[:end_date],
          compare: @options.fetch(:compare)
        )
      end
    end

    include ReportingCommands
  end
end
