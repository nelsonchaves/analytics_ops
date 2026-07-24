# frozen_string_literal: true

module AnalyticsOps
  # Helpers used only when an operator explicitly invokes a Rails Rake task.
  module RailsTasks
    module_function

    def run(command, report_name: nil)
      arguments = [
        command,
        "--config", ENV.fetch("ANALYTICS_OPS_CONFIG", Rails.root.join("config/analytics_ops.yml").to_s)
      ]
      arguments.push("--profile", ENV.fetch("ANALYTICS_OPS_PROFILE")) if ENV.key?("ANALYTICS_OPS_PROFILE")
      if command == "plan"
        arguments.push("--output",
                       ENV.fetch("ANALYTICS_OPS_PLAN", Rails.root.join("tmp/analytics_ops-plan.json").to_s))
      end
      arguments << report_name if report_name

      status = CLI.start(arguments)
      return if status == CLI::SUCCESS

      raise Error, "analytics-ops #{command} exited with status #{status}"
    end
  end

  # Optional Rails hooks. Defining this class performs no Google API calls.
  class Railtie < Rails::Railtie
    OPERATOR_TASKS = {
      doctor: "Validate Analytics Ops configuration, credentials, and API access",
      audit: "Audit configured Google Analytics state without changing it",
      plan: "Write a deterministic Analytics Ops plan",
      verify: "Verify that managed Google Analytics state converges",
      overview: "Show the selected property's Analytics overview",
      portfolio: "Show totals across every configured Analytics property"
    }.freeze

    generators do
      require_relative "../../generators/analytics_ops/install_generator"
    end

    rake_tasks do
      namespace :analytics do
        OPERATOR_TASKS.each do |name, description|
          desc description
          task name => :environment do
            RailsTasks.run(name.to_s)
          end
        end

        desc "Run a built-in report: rake analytics:report[NAME]"
        task :report, [:name] => :environment do |_task, arguments|
          name = arguments[:name]
          raise Error, "analytics:report requires NAME" if name.to_s.empty?

          RailsTasks.run("report", report_name: name)
        end
      end
    end
  end
end
