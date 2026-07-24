# frozen_string_literal: true

module AnalyticsOps
  # Strictly read-only MCP bridge for ChatGPT, Codex, Claude, and other MCP clients.
  class MCPServer
    # Defines the built-in standard-report MCP tool and its strict input schema.
    module StandardReportTool
      private

      def define_standard_report_tool
        owner = self
        server.define_tool(
          name: "analytics_run_report",
          title: "Run Analytics Report",
          description: "Use this to run one safe built-in GA4 standard report for the selected profile.",
          input_schema: standard_report_schema,
          output_schema: OBJECT_OUTPUT,
          annotations: READ_ONLY_ANNOTATIONS
        ) do |report:, profile: nil, last_days: nil, start_date: nil, end_date: nil, compare: false,
              server_context: nil|
          owner.__send__(:respond, server_context) do
            ranges = owner.__send__(
              :date_ranges,
              last_days:,
              start_date:,
              end_date:,
              compare:
            )
            target = owner.__send__(:workspace, profile)
            ranges ? target.report(report, date_ranges: ranges) : target.report(report)
          end
        end
      end

      def standard_report_schema
        {
          type: "object",
          additionalProperties: false,
          required: ["report"],
          properties: PROFILE_INPUT.fetch(:properties).merge(PERIOD_PROPERTIES).merge(
            report: {
              type: "string",
              enum: STANDARD_REPORTS,
              description: "Built-in report name."
            }
          )
        }
      end
    end

    include StandardReportTool
  end
end
