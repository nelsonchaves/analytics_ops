# frozen_string_literal: true

require "fileutils"
require "tmpdir"

begin
  require "rails"
  require "rake"
  require "analytics_ops/rails"
  require_relative "../../lib/generators/analytics_ops/install_generator"
rescue LoadError
  RAILS_INTEGRATION_AVAILABLE = false
else
  RAILS_INTEGRATION_AVAILABLE = true
end

RSpec.describe "optional Rails integration" do
  before do
    skip "Railties is not installed in this compatibility job" unless RAILS_INTEGRATION_AVAILABLE
  end

  it "uses a Railtie and does not construct Google clients during load" do
    expect(AnalyticsOps::Clients::Admin).not_to receive(:new)
    expect(AnalyticsOps::Clients::Data).not_to receive(:new)

    load File.expand_path("../../lib/analytics_ops/rails.rb", __dir__)

    expect(AnalyticsOps::Railtie).to be < Rails::Railtie
    expect(defined?(Rails::Engine)).to eq("constant")
    expect(AnalyticsOps::Railtie).not_to be < Rails::Engine
  end

  it "generates only valid configuration and an executable binstub" do
    Dir.mktmpdir do |directory|
      generator = AnalyticsOps::Generators::InstallGenerator.new([], {}, destination_root: directory)
      generator.invoke_all
      configuration = File.join(directory, "config/analytics_ops.yml")
      executable = File.join(directory, "bin/analytics-ops")

      document = AnalyticsOps::Configuration.load(
        configuration,
        environment: { "GA4_PROPERTY_ID" => "123456789" }
      )

      expect(document.profile("production").property_id).to eq("123456789")
      expect(document.profile("production").streams).to be_empty
      expect(File.stat(executable).mode & 0o777).to eq(0o755)
      expect(File.read(configuration)).not_to match(/private_key|access_token|client_secret/)
    end
  end

  it "lets setup fill the generated configuration without requiring an environment variable" do
    Dir.mktmpdir do |directory|
      generator = AnalyticsOps::Generators::InstallGenerator.new([], {}, destination_root: directory)
      generator.invoke_all
      configuration = File.join(directory, "config/analytics_ops.yml")

      result = AnalyticsOps::Configuration::Writer.new.write_minimal(
        configuration,
        profile: "production",
        property_id: "123456789"
      )

      expect(result).to be_updated
      expect(AnalyticsOps::Configuration.load(configuration).profile("production").property_id)
        .to eq("123456789")
    end
  end

  it "preserves configuration created by service-account setup" do
    Dir.mktmpdir do |directory|
      configuration = File.join(directory, "config/analytics_ops.yml")
      FileUtils.mkdir_p(File.dirname(configuration))
      File.write(configuration, <<~YAML)
        version: 1
        profiles:
          development:
            property_id: "123456789"
      YAML

      generator = AnalyticsOps::Generators::InstallGenerator.new([], {}, destination_root: directory)
      generator.invoke_all

      expect(AnalyticsOps::Configuration.load(configuration).profile("development").property_id)
        .to eq("123456789")
      expect(File).to exist(File.join(directory, "bin/analytics-ops"))
    end
  end

  it "registers the documented operator-only Rake tasks without contacting Google" do
    original_application = Rake.application
    Rake.application = Rake::Application.new
    application_class = Class.new(Rails::Application)
    application_class.config.eager_load = false
    application_class.config.secret_key_base = "fake-test-secret-key-base"
    expect(AnalyticsOps::Clients::Admin).not_to receive(:new)
    expect(AnalyticsOps::Clients::Data).not_to receive(:new)

    application_class.instance.load_tasks

    expect(Rake::Task.tasks.map(&:name)).to include(
      "analytics:doctor",
      "analytics:audit",
      "analytics:plan",
      "analytics:verify",
      "analytics:overview",
      "analytics:portfolio",
      "analytics:report"
    )
  ensure
    Rake.application = original_application if original_application
  end
end
