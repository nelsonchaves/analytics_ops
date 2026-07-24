# frozen_string_literal: true

RSpec.describe "Google client error translation" do
  let(:structured_error_class) do
    Class.new(StandardError) do
      def reason
        "SERVICE_DISABLED"
      end

      def error_metadata
        {
          "service" => "analyticsdata.googleapis.com",
          "detail" => "client_secret=must-not-leak"
        }
      end

      def code
        7
      end
    end
  end

  before { stub_const("StructuredPermissionDeniedError", structured_error_class) }

  it "preserves bounded structured Google details without exposing secrets" do
    translation = AnalyticsOps::Clients.const_get(:ErrorTranslation)

    expect { translation.call { raise StructuredPermissionDeniedError, "Permission denied" } }
      .to raise_error(AnalyticsOps::AuthorizationError) do |error|
        expect(error.remote_reason).to eq("SERVICE_DISABLED")
        expect(error.remote_code).to eq("7")
        expect(error.remote_metadata.fetch("service")).to eq("analyticsdata.googleapis.com")
        expect(error.remote_metadata.fetch("detail")).to eq("client_secret=[REDACTED]")
      end
  end
end
