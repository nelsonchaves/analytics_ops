# frozen_string_literal: true

# Explicit saved-plan application.

module AnalyticsOps
  # Executes only the operations contained in an approved, non-stale plan.
  class Applier
    # Immutable success or partial-reconciliation summary.
    class Result < Resources::Value
      fields :status, :applied, :failed, :remaining
    end

    def initialize(admin:)
      @admin = admin
    end

    def call(plan, confirm: false)
      raise ConfirmationRequiredError, "Applying a plan requires explicit confirmation" unless confirm

      current = @admin.snapshot(plan.property_id)
      unless current.fingerprint == plan.snapshot_fingerprint
        raise StalePlanError, "Remote state changed after this plan was generated; create a new plan"
      end

      applied = []
      plan.changes.each_with_index do |change, index|
        @admin.apply_change(change, property_id: plan.property_id)
        applied << change.to_h
      rescue StandardError => error
        result = Result.new(
          status: "partial",
          applied:,
          failed: failure(change, error),
          remaining: plan.changes.drop(index + 1).map(&:to_h)
        )
        raise PartialApplyError.new("Apply stopped after #{applied.length} successful changes", result:)
      end

      Result.new(status: "applied", applied:, failed: nil, remaining: [])
    end

    private

    def failure(change, error)
      {
        "change" => change.to_h,
        "error_type" => error.class.name,
        "message" => Redaction.message(error.message).slice(0, 500)
      }
    end
  end
end
