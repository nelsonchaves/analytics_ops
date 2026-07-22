# frozen_string_literal: true

require "tmpdir"

RSpec.describe AnalyticsOps::Configuration::Writer do
  it "atomically creates the smallest valid production configuration" do
    Dir.mktmpdir("analytics-ops-writer") do |directory|
      path = File.join(directory, "config", "analytics_ops.yml")

      result = described_class.new.write_minimal(path, profile: "production", property_id: "123456789")
      configuration = AnalyticsOps::Configuration.load(path)

      expect(result).to be_created
      expect(result.path).to eq(File.expand_path(path))
      expect(configuration.profile("production").property_id).to eq("123456789")
      expect(File.binread(path)).to include("property_id: \"123456789\"")
    end
  end

  it "leaves an existing matching configuration byte-for-byte unchanged" do
    Dir.mktmpdir("analytics-ops-writer") do |directory|
      path = File.join(directory, "analytics_ops.yml")
      writer = described_class.new
      writer.write_minimal(path, profile: "production", property_id: "123456789")
      original = File.binread(path)

      result = writer.write_minimal(path, profile: "production", property_id: "123456789")

      expect(result).not_to be_created
      expect(File.binread(path)).to eq(original)
    end
  end

  it "never overwrites a profile that targets another property" do
    Dir.mktmpdir("analytics-ops-writer") do |directory|
      path = File.join(directory, "analytics_ops.yml")
      writer = described_class.new
      writer.write_minimal(path, profile: "production", property_id: "123456789")

      expect { writer.write_minimal(path, profile: "production", property_id: "987654321") }
        .to raise_error(AnalyticsOps::ConfigurationError, /will not overwrite/)
      expect(AnalyticsOps::Configuration.load(path).profile("production").property_id).to eq("123456789")
    end
  end

  it "does not replace a file created concurrently" do
    Dir.mktmpdir("analytics-ops-writer") do |directory|
      path = File.join(directory, "analytics_ops.yml")
      original = "created by another process\n"
      File.write(path, original)
      first_target_check = true
      allow(File).to receive(:exist?).and_wrap_original do |method, candidate|
        if candidate == File.expand_path(path) && first_target_check
          first_target_check = false
          false
        else
          method.call(candidate)
        end
      end

      expect do
        described_class.new.write_minimal(path, profile: "production", property_id: "123456789")
      end.to raise_error(AnalyticsOps::ConfigurationError, /created by another process/)
      expect(File.binread(path)).to eq(original)
    end
  end
end
