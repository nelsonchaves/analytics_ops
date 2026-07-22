# frozen_string_literal: true

module AnalyticsOps
  # Helpers used only when an operator explicitly invokes a Rails Rake task.
  module RailsTasks
    module_function

    def run(command, report_name: nil)
      arguments = [
        command,
        "--config", ENV.fetch("ANALYTICS_OPS_CONFIG", Rails.root.join("config/analytics_ops.yml").to_s),
        "--profile", ENV.fetch("ANALYTICS_OPS_PROFILE", Rails.env.to_s)
      ]
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
    generators do
      require_relative "../../generators/analytics_ops/install_generator"
    end

    rake_tasks do
      namespace :analytics do
        desc "Validate Analytics Ops configuration, credentials, and API access"
        task doctor: :environment do
          RailsTasks.run("doctor")
        end

        desc "Audit configured Google Analytics state without changing it"
        task audit: :environment do
          RailsTasks.run("audit")
        end

        desc "Write a deterministic Analytics Ops plan"
        task plan: :environment do
          RailsTasks.run("plan")
        end

        desc "Verify that managed Google Analytics state converges"
        task verify: :environment do
          RailsTasks.run("verify")
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
