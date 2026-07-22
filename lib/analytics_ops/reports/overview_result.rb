# frozen_string_literal: true

module AnalyticsOps
  module Reports
    # Immutable collection of the bounded reports that make up an overview.
    class OverviewResult
      MAX_REPORTS = 5
      PROPERTY_ID = /\A\d{1,50}\z/

      attr_reader :property_id, :reports, :property_quota

      def initialize(property_id:, reports:)
        unless property_id.is_a?(String) && PROPERTY_ID.match?(property_id)
          raise RemoteError, "Overview property ID is invalid"
        end
        unless reports.is_a?(Array) && reports.length.between?(1, MAX_REPORTS) &&
               reports.all? { |report| report.is_a?(Result) && report.kind == "standard" }
          raise RemoteError, "Overview must contain 1 to #{MAX_REPORTS} standard report results"
        end

        names = reports.map(&:name)
        raise RemoteError, "Overview report names must be unique" unless names.uniq.length == names.length

        @property_id = property_id.dup.freeze
        @reports = reports.dup.freeze
        @property_quota = Canonical.immutable(latest_quota)
        freeze
      end

      def report(name)
        reports.find { |result| result.name == name.to_s } ||
          raise(KeyError, "Unknown overview report #{name.inspect}")
      end

      def to_h
        {
          "property_id" => property_id,
          "reports" => reports.map(&:to_h),
          "property_quota" => property_quota
        }
      end

      private

      def latest_quota
        reports.reverse_each do |result|
          quota = result.metadata["property_quota"]
          return quota if quota
        end
        {}
      end
    end
  end
end
