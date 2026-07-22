# frozen_string_literal: true

# Shared deterministic value helpers.

require "digest"
require "json"

module AnalyticsOps
  # Deterministic serialization shared by snapshots and saved plans.
  module Canonical
    module_function

    def normalize(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, child), result|
          result[key.to_s] = normalize(child)
        end.sort.to_h
      when Array
        value.map { |child| normalize(child) }
      else
        value
      end
    end

    def json(value)
      JSON.generate(normalize(value))
    end

    def fingerprint(value)
      "sha256:#{Digest::SHA256.hexdigest(json(value))}"
    end

    def deep_freeze(value)
      case value
      when Hash
        value.each do |key, child|
          deep_freeze(key)
          deep_freeze(child)
        end
      when Array
        value.each { |child| deep_freeze(child) }
      end

      value.freeze
    end

    def immutable(value)
      deep_freeze(copy(value))
    end

    def copy(value)
      case value
      when Hash
        value.to_h { |key, child| [copy(key), copy(child)] }
      when Array
        value.map { |child| copy(child) }
      when String
        value.dup
      else
        value
      end
    end
  end
end
