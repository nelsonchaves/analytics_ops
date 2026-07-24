# frozen_string_literal: true

require "json"
require "openssl"
require "tmpdir"

RSpec.describe AnalyticsOps::ServiceAccount do
  def write_service_account(directory, overrides = {})
    path = File.join(directory, "service-account.json")
    document = {
      "type" => "service_account",
      "project_id" => "example-analytics-project",
      "private_key_id" => "obviously-fake-key-id",
      "private_key" => OpenSSL::PKey::RSA.generate(1024).to_pem,
      "client_email" => "analytics-ops@example-analytics-project.iam.gserviceaccount.com",
      "client_id" => "100000000000000000001",
      "auth_uri" => "https://accounts.google.com/o/oauth2/auth",
      "token_uri" => "https://oauth2.googleapis.com/token"
    }.merge(overrides)
    File.write(path, JSON.generate(document))
    path
  end

  it "loads only a Google service-account key and requests bounded read or edit scopes" do
    Dir.mktmpdir("analytics-ops-service-account") do |directory|
      identity = described_class.new(write_service_account(directory))

      read = identity.send(:credentials, access: :read)
      edit = identity.send(:credentials, access: :edit)

      expect(read).to be_a(Google::Auth::ServiceAccountCredentials)
      expect(Array(read.scope)).to eq([described_class::READ_SCOPE])
      expect(Array(edit.scope)).to contain_exactly(described_class::READ_SCOPE, described_class::EDIT_SCOPE)
      expect { identity.send(:credentials, access: :unknown) }.to raise_error(ArgumentError, /:read or :edit/)
    end
  end

  it "remembers only the canonical key path in a mode-0600 user connection file" do
    Dir.mktmpdir("analytics-ops-service-account") do |directory|
      key_path = write_service_account(directory)
      store = described_class::Store.new(path: File.join(directory, "settings", "connection.json"))

      result = store.write(key_path)
      saved = JSON.parse(File.read(result))

      expect(store.read).to eq(File.realpath(key_path))
      expect(saved).to eq(
        "version" => described_class::Store::VERSION,
        "connections" => { "default" => File.realpath(key_path) },
        "configs" => {}
      )
      expect(File.stat(result).mode & 0o777).to eq(0o600)
      expect(File.stat(File.dirname(result)).mode & 0o777).to eq(0o700)
      expect(File.read(result)).not_to include("PRIVATE KEY", "client_email")
    end
  end

  it "loads a remembered key when no explicit path is provided" do
    Dir.mktmpdir("analytics-ops-service-account") do |directory|
      key_path = write_service_account(directory)
      store = described_class::Store.new(path: File.join(directory, "connection.json"))
      store.write(key_path)

      expect(described_class.load(store:).path).to eq(File.realpath(key_path))
    end
  end

  it "remembers named connections per configuration profile and switches without exposing paths" do
    Dir.mktmpdir("analytics-ops-service-account") do |directory|
      first_directory = File.join(directory, "first")
      second_directory = File.join(directory, "second")
      Dir.mkdir(first_directory)
      Dir.mkdir(second_directory)
      first_key = write_service_account(first_directory)
      second_key = write_service_account(
        second_directory,
        "client_email" => "analytics-ops@example-client-project.iam.gserviceaccount.com"
      )
      config = File.join(directory, "config", "analytics_ops.yml")
      store = described_class::Store.new(path: File.join(directory, "settings", "connection.json"))

      store.write(first_key, name: "primary", config:, profile: "production")
      store.write(second_key, name: "client_b", config:, profile: "client_b", select: false)

      expect(store.read(config:, profile: "production")).to eq(File.realpath(first_key))
      expect(store.read(config:, profile: "client_b")).to eq(File.realpath(second_key))
      expect(store.selected_profile(config:)).to eq("production")

      selection = store.select(config:, profile: "client_b")

      expect(selection).to eq("profile" => "client_b", "connection" => "client_b")
      expect(store.selected_profile(config:)).to eq("client_b")
      expect(store.summaries).to contain_exactly(
        { "name" => "primary", "available" => true, "in_use" => true },
        { "name" => "client_b", "available" => true, "in_use" => true }
      )
      expect(store.summaries.to_s).not_to include(directory)
    end
  end

  it "reads and safely migrates the version-1 single-connection format" do
    Dir.mktmpdir("analytics-ops-service-account") do |directory|
      key_path = write_service_account(directory)
      store = described_class::Store.new(path: File.join(directory, "connection.json"))
      File.write(
        store.path,
        JSON.generate("version" => described_class::Store::LEGACY_VERSION,
                      "service_account_path" => File.realpath(key_path))
      )

      expect(store.read).to eq(File.realpath(key_path))
      expect(store.profile_connection(config: "config/analytics_ops.yml", profile: "production")).to eq("default")

      store.write(key_path, name: "production", config: "config/analytics_ops.yml", profile: "production")
      saved = JSON.parse(File.read(store.path))
      expect(saved.fetch("version")).to eq(described_class::Store::VERSION)
      expect(saved.fetch("connections")).to eq("production" => File.realpath(key_path))
    end
  end

  it "requires an explicit name when several unassociated connections exist" do
    Dir.mktmpdir("analytics-ops-service-account") do |directory|
      first_directory = File.join(directory, "first")
      second_directory = File.join(directory, "second")
      Dir.mkdir(first_directory)
      Dir.mkdir(second_directory)
      store = described_class::Store.new(path: File.join(directory, "connection.json"))
      store.write(write_service_account(first_directory), name: "first")
      store.write(write_service_account(second_directory), name: "second")

      expect { store.read }.to raise_error(AnalyticsOps::AuthenticationError, /--connection NAME/)
      expect(store.read(name: "second")).to include("/second/service-account.json")
    end
  end

  it "chooses a collision-free default when separate apps both use production" do
    Dir.mktmpdir("analytics-ops-service-account") do |directory|
      first_directory = File.join(directory, "first")
      second_directory = File.join(directory, "second")
      Dir.mkdir(first_directory)
      Dir.mkdir(second_directory)
      first_key = write_service_account(first_directory)
      second_key = write_service_account(
        second_directory,
        "client_email" => "analytics-ops@example-second-project.iam.gserviceaccount.com"
      )
      store = described_class::Store.new(path: File.join(directory, "connection.json"))
      first_config = File.join(directory, "first_app", "analytics_ops.yml")
      second_config = File.join(directory, "second_app", "analytics_ops.yml")
      store.write(first_key, name: "production", config: first_config, profile: "production")

      name = store.connection_name_for(
        second_key,
        preferred: "production",
        config: second_config,
        profile: "production"
      )
      store.write(second_key, name:, config: second_config, profile: "production")

      expect(name).to eq("production_2")
      expect(store.read(config: first_config, profile: "production")).to eq(File.realpath(first_key))
      expect(store.read(config: second_config, profile: "production")).to eq(File.realpath(second_key))
    end
  end

  it "fails closed for a missing, malformed, wrong-type, or oversized key" do
    Dir.mktmpdir("analytics-ops-service-account") do |directory|
      missing = File.join(directory, "missing.json")
      malformed = File.join(directory, "malformed.json")
      wrong_type = File.join(directory, "wrong-type.json")
      oversized = File.join(directory, "oversized.json")
      File.write(malformed, "{")
      File.write(wrong_type, JSON.generate("type" => "authorized_user", "private_key" => "do-not-echo"))
      File.write(oversized, "x" * (described_class::MAX_KEY_BYTES + 1))

      expect { described_class.new(missing) }.to raise_error(AnalyticsOps::AuthenticationError, /unavailable/)
      expect { described_class.new(malformed) }.to raise_error(AnalyticsOps::AuthenticationError, /not a valid/)
      expect { described_class.new(wrong_type) }
        .to raise_error(AnalyticsOps::AuthenticationError, /not a Google service-account/)
      expect { described_class.new(oversized) }.to raise_error(AnalyticsOps::AuthenticationError, /too large/)
    end
  end

  it "warns when a key is broadly readable or stored inside a Git repository" do
    Dir.mktmpdir("analytics-ops-service-account") do |directory|
      FileUtils.mkdir_p(File.join(directory, ".git"))
      key_path = write_service_account(directory)
      File.chmod(0o644, key_path)

      warnings = described_class.new(key_path).security_warnings

      expect(warnings).to include(match(/permissions are 0644.*chmod 600/), match(/inside a Git repository/))
      expect(warnings.join).not_to include(directory)
    end
  end

  it "requires an explicit first-time setup and rejects malformed saved connection state" do
    Dir.mktmpdir("analytics-ops-service-account") do |directory|
      store = described_class::Store.new(path: File.join(directory, "connection.json"))

      expect { store.read }.to raise_error(
        AnalyticsOps::AuthenticationError,
        %r{setup --service-account /absolute/path}
      )

      File.write(store.path, JSON.generate("version" => 1, "unexpected" => true))
      expect { store.read }.to raise_error(AnalyticsOps::AuthenticationError, /saved.*connection is invalid/i)

      File.write(
        store.path,
        JSON.generate(
          "version" => described_class::Store::VERSION,
          "connections" => { "primary" => "/tmp/obviously-fake-key.json" },
          "configs" => {
            "/tmp/analytics_ops.yml" => {
              "selected_profile" => "production",
              "profile_connections" => { "production" => "missing" }
            }
          }
        )
      )
      expect { store.read }.to raise_error(AnalyticsOps::AuthenticationError, /saved.*connection is invalid/i)
    end
  end
end
