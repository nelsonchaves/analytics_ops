# frozen_string_literal: true

module AnalyticsOps
  class CLI
    # Formats gem-owned values for terminal and automation consumers.
    class Presenter
      OVERVIEW_LABELS = {
        "overview_totals" => "Totals",
        "overview_trend" => "Daily trend",
        "overview_acquisition" => "Traffic acquisition",
        "overview_landing_pages" => "Landing pages",
        "overview_devices" => "Devices"
      }.freeze

      def initialize(out:, format:)
        @out = out
        @format = format
      end

      def render(value, status: CLI::SUCCESS)
        case @format
        when "json"
          @out.write(json(value))
        when "csv"
          @out.write(csv(value))
        else
          @out.puts(human(value))
        end
        status
      end

      def render_properties(accounts)
        return render(accounts) unless @format == "human"
        return write("No accessible Google Analytics properties found") if accounts.empty?

        lines = accounts.flat_map do |account|
          ["Account #{account.id}: #{account.display_name}"] + account.properties.map do |property|
            "  Property #{property.fetch("id")}: #{property.fetch("display_name")}"
          end
        end
        write(lines.join("\n"))
      end

      def json(value)
        payload = serializable(value)
        "#{JSON.pretty_generate(Canonical.normalize(payload))}\n"
      end

      def human_plan(plan, detailed: false)
        lines = [
          "Plan for profile #{plan.profile} / property #{plan.property_id}",
          "Snapshot: #{plan.snapshot_fingerprint}",
          "Changes: #{plan.changes.length}; findings: #{plan.findings.length}"
        ]
        plan.changes.each do |change|
          lines << "  #{change.operation.upcase.ljust(6)} #{change.resource_type} #{change.resource_identity}"
          next unless detailed

          lines << "    before: #{JSON.generate(Canonical.normalize(change.before))}"
          lines << "    after:  #{JSON.generate(Canonical.normalize(change.after))}"
          lines << "    rollback: #{change.rollback}"
        end
        plan.findings.each do |finding|
          lines << "  #{finding.severity.upcase.ljust(12)} #{finding.resource_identity}: #{finding.message}"
        end
        lines.join("\n")
      end

      private

      def csv(value)
        unless value.is_a?(Reports::Result)
          raise OptionParser::InvalidArgument, "CSV output is only valid for report results"
        end

        lines = [value.headers]
        value.rows.each { |row| lines << value.headers.map { |header| csv_cell(row.fetch(header)) } }
        "#{lines.map { |line| line.map { |cell| csv_field(cell) }.join(",") }.join("\n")}\n"
      end

      def csv_cell(value)
        string = value.to_s
        string.match?(/\A[=+\-@]/) ? "'#{string}" : string
      end

      def csv_field(value)
        string = value.to_s
        return string unless string.match?(/[",\r\n]/)

        "\"#{string.gsub("\"", "\"\"")}\""
      end

      def serializable(value)
        case value
        when Array
          value.map { |item| serializable(item) }
        when Hash
          value.to_h { |key, item| [key.to_s, serializable(item)] }
        else
          value.respond_to?(:to_h) ? serializable(value.to_h) : value
        end
      end

      def human(value)
        case value
        when Plan
          human_plan(value)
        when Snapshot
          "Snapshot #{value.fingerprint}\n#{JSON.pretty_generate(Canonical.normalize(value.to_h))}"
        when Workspace::DoctorResult
          human_doctor(value)
        when Workspace::Verification
          "#{value.converged ? "Converged" : "Drift found"}: #{value.plan.changes.length} planned changes"
        when Applier::Result
          "Apply #{value.status}: #{value.applied.length} changes completed"
        when Reports::Result
          human_report(value)
        when Reports::OverviewResult
          human_overview(value)
        when Array
          human_discovery(value)
        else
          JSON.pretty_generate(Canonical.normalize(serializable(value)))
        end
      end

      def human_doctor(value)
        value.checks.map do |check|
          "#{check.fetch("status").upcase.ljust(11)} #{check.fetch("name")}: #{check.fetch("detail")}"
        end.join("\n")
      end

      def human_report(result)
        ["Report #{result.name} (#{result.kind}) — #{result.row_count} rows", *human_report_table(result)].join("\n")
      end

      def human_overview(overview)
        lines = ["Overview for property #{overview.property_id} — previous 28 complete days"]
        overview.reports.each do |report|
          lines << ""
          lines << OVERVIEW_LABELS.fetch(report.name, report.name)
          lines.concat(human_report_table(report))
        end
        lines.join("\n")
      end

      def human_report_table(result)
        return ["No rows returned"] if result.rows.empty?

        widths = result.headers.to_h do |header|
          values = result.rows.map { |row| row.fetch(header).to_s }
          [header, ([header.length] + values.map(&:length)).max.clamp(1, 60)]
        end
        lines = [table_row(result.headers, widths)]
        lines << result.headers.map { |header| "-" * widths.fetch(header) }.join("-+-")
        result.rows.each do |row|
          lines << table_row(result.headers.map { |header| row.fetch(header) }, widths, headers: result.headers)
        end
        lines
      end

      def table_row(values, widths, headers: values)
        values.zip(headers).map do |value, header|
          value.to_s.slice(0, widths.fetch(header)).ljust(widths.fetch(header))
        end.join(" | ")
      end

      def human_discovery(accounts)
        return "No accessible Google Analytics accounts found" if accounts.empty?

        accounts.flat_map do |account|
          lines = ["Account #{account.id}: #{account.display_name}"]
          account.properties.each do |property|
            lines << "  Property #{property.fetch("id")}: #{property.fetch("display_name")}"
            property.fetch("streams").each do |stream|
              lines << "    Stream #{stream.fetch("id")}: #{stream.fetch("display_name")} (#{stream.fetch("type")})"
            end
          end
          lines
        end.join("\n")
      end

      def write(message)
        @out.puts message
        CLI::SUCCESS
      end
    end
  end
end
