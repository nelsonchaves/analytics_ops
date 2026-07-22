# frozen_string_literal: true

require_relative "../analytics_ops"

module AnalyticsOps
  # Command-line entry point. Requiring or constructing it performs no I/O.
  class CLI
    SUCCESS = 0
    USAGE_ERROR = 64

    def self.start(arguments, out: $stdout, err: $stderr)
      new(arguments, out:, err:).call
    end

    def initialize(arguments, out:, err:)
      @arguments = arguments.dup
      @out = out
      @err = err
    end

    def call
      command = @arguments.shift

      return write(@out, help) if [nil, "help", "--help", "-h"].include?(command)
      return write(@out, AnalyticsOps::VERSION) if ["version", "--version", "-v"].include?(command)

      unknown_command(command)
    end

    private

    def write(stream, message, status = SUCCESS)
      stream.puts message
      status
    end

    def unknown_command(command)
      @err.puts "Unknown command: #{command}"
      write(@err, "Run `analytics-ops help` for available commands.", USAGE_ERROR)
    end

    def help
      <<~HELP
        Analytics Ops #{AnalyticsOps::VERSION}
        Google Analytics 4 configuration as code and reporting for Ruby and Rails.

        Usage:
          analytics-ops COMMAND

        Commands:
          help       Show this help
          version    Print the installed version

        Status:
          The public API is under active development. Administrative and reporting
          commands will be introduced behind read-only defaults.
      HELP
    end
  end
end
