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
        "service_account_path" => File.realpath(key_path)
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

  it "requires an explicit first-time setup and rejects malformed saved connection state" do
    Dir.mktmpdir("analytics-ops-service-account") do |directory|
      store = described_class::Store.new(path: File.join(directory, "connection.json"))

      expect { store.read }.to raise_error(
        AnalyticsOps::AuthenticationError,
        %r{setup --service-account /absolute/path}
      )

      File.write(store.path, JSON.generate("version" => 1, "unexpected" => true))
      expect { store.read }.to raise_error(AnalyticsOps::AuthenticationError, /saved.*connection is invalid/i)
    end
  end
end
