# frozen_string_literal: true

# Development and compatibility dependencies.

source "https://rubygems.org"

# Specify your gem's dependencies in analytics_ops.gemspec
gemspec

gem "irb"
gem "rake", "~> 13.0"

gem "rbs", "~> 4.0", require: false
gem "rspec", "~> 3.0"

gem "rubocop", "~> 1.21"
# parallel 2.x requires Ruby 3.3, while Analytics Ops supports Ruby 3.2.
# RuboCop accepts parallel 1.x, so keep this development-only dependency there.
gem "parallel", "< 2.0"

gem "bundler-audit", "~> 0.9", require: false
