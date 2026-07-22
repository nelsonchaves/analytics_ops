# frozen_string_literal: true

require "bundler/gem_tasks"
require "fileutils"
require "json"
require "rubygems/package"
require "rspec/core/rake_task"
require "rubocop/rake_task"
require "tmpdir"

RSpec::Core::RakeTask.new(:spec)

RuboCop::RakeTask.new do |task|
  task.options = ["--config", File.expand_path(".rubocop.yml", __dir__)]
end

desc "Validate public RBS declarations"
task :rbs do
  sh Gem.ruby, Gem.bin_path("rbs", "rbs"), "-I", "sig", "validate"
end

desc "Validate committed configuration and plan schemas"
task :schemas do
  require_relative "lib/analytics_ops"

  configuration = JSON.parse(File.binread("docs/configuration-schema-v1.json"))
  plan = JSON.parse(File.binread("docs/plan-schema-v1.json"))

  unless configuration == AnalyticsOps::Configuration::SCHEMA
    abort "Configuration schema differs from the runtime schema"
  end
  abort "Plan schema must declare version 1" unless plan.dig("properties", "format_version", "const") == 1
end

desc "Validate local documentation links"
task :docs do
  markdown_files = Dir.glob(["*.md", "docs/*.md"])
  missing = markdown_files.flat_map do |file|
    File.binread(file).scan(/\[[^\]]+\]\(([^)]+)\)/).filter_map do |(link)|
      next if link.match?(/\A(?:https?:|mailto:|#)/)

      target = link.split("#", 2).first
      next if target.empty?

      "#{file}: #{link}" unless File.exist?(File.expand_path(target, File.dirname(file)))
    end
  end
  abort "Missing documentation links:\n#{missing.join("\n")}" unless missing.empty?
end

namespace :security do
  desc "Scan tracked and untracked project files for credential-shaped material"
  task :scan do
    patterns = {
      "private key" => %r{-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----\s+[A-Za-z0-9+/=\r\n]{40,}},
      "Google API key" => /AIza[0-9A-Za-z_-]{35}/,
      "Google OAuth token" => /ya29\.[0-9A-Za-z_-]{20,}/,
      "GitHub token" => /gh[pousr]_[0-9A-Za-z]{20,}/,
      "bearer token" => /Bearer\s+[0-9A-Za-z._~-]{20,}/i
    }
    files = IO.popen(%w[git ls-files -co --exclude-standard], &:read).split("\n")
    findings = files.filter_map do |file|
      next unless File.file?(file)

      contents = File.binread(file)
      label = patterns.find { |_name, pattern| contents.match?(pattern) }&.first
      "#{file}: #{label}" if label
    rescue ArgumentError
      nil
    end

    abort "Credential-shaped material found:\n#{findings.join("\n")}" unless findings.empty?
  end
end

namespace :release do
  desc "Build and inspect the exact RubyGem payload"
  task :inspect do
    require_relative "lib/analytics_ops/version"

    path = ENV.fetch("ANALYTICS_OPS_GEM_PATH", "pkg/analytics_ops-#{AnalyticsOps::VERSION}.gem")
    FileUtils.mkdir_p(File.dirname(path))
    sh Gem.ruby, "-S", "gem", "build", "analytics_ops.gemspec", "--output", path

    package = Gem::Package.new(path)
    files = package.spec.files.sort
    documentation = %w[
      CHANGELOG.md
      CODE_OF_CONDUCT.md
      CONTRIBUTING.md
      LICENSE.txt
      README.md
      SECURITY.md
    ]
    unexpected = files.reject do |file|
      documentation.include?(file) ||
        file.start_with?("lib/", "exe/", "sig/") ||
        (file.start_with?("docs/") && file != "docs/product-plan.txt")
    end
    abort "Unexpected packaged files: #{unexpected.join(", ")}" unless unexpected.empty?
    abort "Product planning document must not ship" if files.include?("docs/product-plan.txt")
    abort "Missing packaged executable" unless package.spec.executables == ["analytics-ops"]
    abort "Missing packaged RBS signature" unless files.include?("sig/analytics_ops.rbs")

    Dir.mktmpdir("analytics-ops-package") do |directory|
      package.extract_files(directory)
      executable = File.join(directory, "exe/analytics-ops")
      abort "Packaged executable is not executable" unless File.executable?(executable)

      verification = <<~RUBY
        require "analytics_ops"
        root = File.realpath(ARGV.fetch(0))
        feature = $LOADED_FEATURES.find { |path| File.basename(path) == "analytics_ops.rb" }
        packaged_lib = File.join(root, "lib") + File::SEPARATOR
        abort unless feature && File.realpath(feature).start_with?(packaged_lib)
        abort unless AnalyticsOps::VERSION == "#{AnalyticsOps::VERSION}"
      RUBY
      required = Bundler.with_unbundled_env do
        system(
          { "BUNDLE_GEMFILE" => nil, "RUBYOPT" => nil },
          Gem.ruby,
          "--disable-gems",
          "-rrubygems",
          "-I#{directory}/lib",
          "-e",
          verification,
          directory,
          chdir: directory
        )
      end
      abort "Packaged library cannot be required in isolation" unless required
    end
  end
end

task default: %i[spec rubocop rbs schemas docs security:scan]
