# frozen_string_literal: true

require "open3"
require "rbconfig"
require "tempfile"

RSpec.describe "network safety" do
  let(:configuration) do
    <<~YAML
      version: 1
      profiles:
        test:
          property_id: "123456789"
          streams: {}
          key_events: []
          custom_dimensions: []
          custom_metrics: []
          manual_requirements: []
    YAML
  end

  it "requires the gem and loads YAML without opening a network connection" do
    Tempfile.create(["analytics-ops-network-safety", ".yml"]) do |file|
      file.write(configuration)
      file.flush
      script = <<~RUBY
        require "socket"
        class << TCPSocket
          def new(*) = raise("network attempted through TCPSocket")
          alias open new
        end
        class << Socket
          def tcp(*) = raise("network attempted through Socket.tcp")
        end
        require "analytics_ops"
        connection = AnalyticsOps::Connection.new
        document = AnalyticsOps::Configuration.load(ARGV.fetch(0), environment: {})
        abort "wrong connection" unless connection.is_a?(AnalyticsOps::Connection)
        abort "wrong property" unless document.profile("test").property_id == "123456789"
      RUBY

      _output, error, status = Open3.capture3(
        RbConfig.ruby,
        "-I#{File.expand_path("../../lib", __dir__)}",
        "-e", script,
        file.path
      )

      expect(status).to be_success, error
    end
  end
end
