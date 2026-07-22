# frozen_string_literal: true

# Release package contract.

require_relative "lib/analytics_ops/version"

Gem::Specification.new do |spec|
  spec.name = "analytics_ops"
  spec.version = AnalyticsOps::VERSION
  spec.authors = ["Nelson Chaves"]
  spec.email = ["nelsonchavespro@gmail.com"]

  spec.summary = "Manage Google Analytics 4 configuration and reports safely from Ruby and Rails."
  spec.description = <<~DESCRIPTION.strip
    Analytics Ops provides configuration-as-code, drift detection, explicit
    plans, safe application, and reporting for Google Analytics 4 properties.
    Its plain-Ruby core uses Google's official API clients, with optional Rails
    integration and no network access during application boot.
  DESCRIPTION
  spec.homepage = "https://github.com/nelsonchaves/analytics_ops#readme"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"
  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/nelsonchaves/analytics_ops"
  spec.metadata["changelog_uri"] = "https://github.com/nelsonchaves/analytics_ops/blob/main/CHANGELOG.md"
  spec.metadata["bug_tracker_uri"] = "https://github.com/nelsonchaves/analytics_ops/issues"
  spec.metadata["documentation_uri"] = "https://github.com/nelsonchaves/analytics_ops/tree/main/docs"
  spec.metadata["rubygems_mfa_required"] = "true"

  documentation = %w[
    CHANGELOG.md
    CODE_OF_CONDUCT.md
    CONTRIBUTING.md
    LICENSE.txt
    README.md
    SECURITY.md
  ].freeze
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).select do |file|
      documentation.include?(file) ||
        file.start_with?("lib/", "exe/", "sig/") ||
        (file.start_with?("docs/") && file != "docs/product-plan.txt")
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "google-analytics-admin", "~> 0.8.0"
  spec.add_dependency "google-analytics-data", "~> 0.9.0"
end
