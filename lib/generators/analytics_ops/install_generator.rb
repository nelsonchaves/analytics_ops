# frozen_string_literal: true

require "rails/generators"

module AnalyticsOps
  module Generators
    # Installs only configuration and a project-local CLI launcher.
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      desc "Create config/analytics_ops.yml and bin/analytics-ops"

      def copy_configuration
        template "analytics_ops.yml", "config/analytics_ops.yml"
      end

      def copy_executable
        copy_file "analytics-ops", "bin/analytics-ops"
        File.chmod(0o755, File.join(destination_root, "bin/analytics-ops"))
      end
    end
  end
end
