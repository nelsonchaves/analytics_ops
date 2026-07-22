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
          ["Account #{display(account.id)}: #{display(account.display_name)}"] + account.properties.map do |property|
            "  Property #{display(property.fetch("id"))}: #{display(property.fetch("display_name"))}"
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
          "Plan for profile #{display(plan.profile)} / property #{display(plan.property_id)}",
          "Snapshot: #{display(plan.snapshot_fingerprint)}",
          "Changes: #{plan.changes.length}; findings: #{plan.findings.length}"
        ]
        plan.changes.each do |change|
          lines.concat(human_plan_change(change, detailed:))
        end
        plan.findings.each do |finding|
          lines << "  #{display(finding.severity).upcase.ljust(12)} #{display(finding.resource_identity)}: " \
                   "#{display(finding.message)}"
        end
        lines.join("\n")
      end

      private

      def csv(value)
        unless value.is_a?(Reports::Result)
          raise OptionParser::InvalidArgument, "CSV output is only valid for report results"
        end

        lines = [value.headers.map { |header| csv_cell(header) }]
        value.rows.each { |row| lines << value.headers.map { |header| csv_cell(row.fetch(header)) } }
        "#{lines.map { |line| line.map { |cell| csv_field(cell) }.join(",") }.join("\n")}\n"
      end

      def human_plan_change(change, detailed:)
        lines = [
          "  #{display(change.operation).upcase.ljust(6)} #{display(change.resource_type)} " \
          "#{display(change.resource_identity)}"
        ]
        return lines unless detailed

        lines << "    before: #{display(JSON.generate(Canonical.normalize(change.before)))}"
        lines << "    after:  #{display(JSON.generate(Canonical.normalize(change.after)))}"
        lines << "    rollback: #{display(change.rollback)}"
      end

      def csv_cell(value)
        string = value.to_s.gsub(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/, "?")
        dangerous = string.match?(/\A(?:[\p{Space}\uFEFF]*[=+\-@]|[\t\r\n])/)
        dangerous ? "'#{string}" : string
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
          "Snapshot #{display(value.fingerprint)}\n" \
          "#{JSON.pretty_generate(Canonical.normalize(safe_human_value(value.to_h)))}"
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
          status = display(check.fetch("status")).upcase.ljust(11)
          "#{status} #{display(check.fetch("name"))}: #{display(check.fetch("detail"))}"
        end.join("\n")
      end

      def human_report(result)
        [
          "Report #{display(result.name)} (#{display(result.kind)}) — #{result.row_count} rows",
          *human_report_table(result)
        ].join("\n")
      end

      def human_overview(overview)
        lines = ["Overview for property #{display(overview.property_id)} — previous 28 complete days"]
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
          values = result.rows.map { |row| display(row.fetch(header)) }
          [header, ([display(header).length] + values.map(&:length)).max.clamp(1, 60)]
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
          display(value).slice(0, widths.fetch(header)).ljust(widths.fetch(header))
        end.join(" | ")
      end

      def human_discovery(accounts)
        return "No accessible Google Analytics accounts found" if accounts.empty?

        accounts.flat_map do |account|
          lines = ["Account #{display(account.id)}: #{display(account.display_name)}"]
          account.properties.each do |property|
            lines << "  Property #{display(property.fetch("id"))}: #{display(property.fetch("display_name"))}"
            property.fetch("streams").each do |stream|
              lines << "    Stream #{display(stream.fetch("id"))}: #{display(stream.fetch("display_name"))} " \
                       "(#{display(stream.fetch("type"))})"
            end
          end
          lines
        end.join("\n")
      end

      def display(value)
        Redaction.message(value)
      end

      def safe_human_value(value)
        case value
        when Hash
          value.to_h { |key, child| [key, safe_human_value(child)] }
        when Array
          value.map { |child| safe_human_value(child) }
        when String
          display(value)
        else
          value
        end
      end

      def write(message)
        @out.puts message
        CLI::SUCCESS
      end
    end
  end
end
