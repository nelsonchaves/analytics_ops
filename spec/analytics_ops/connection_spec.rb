# frozen_string_literal: true

RSpec.describe AnalyticsOps::Connection do
  let(:admin) { instance_double(AnalyticsOps::Clients::Admin) }
  let(:data) { instance_double(AnalyticsOps::Clients::Data) }
  let(:connection) { described_class.new(admin:, data:) }

  it "discovers properties without loading streams for setup" do
    accounts = [AnalyticsOps::Resources::Account.new(
      id: "100000001",
      name: "accounts/100000001",
      display_name: "Example account",
      properties: [property.to_h]
    )]
    allow(admin).to receive(:discover).with(include_streams: false).and_return(accounts)

    expect(connection.properties).to equal(accounts)
  end

  it "keeps detailed discovery available" do
    allow(admin).to receive(:discover).with(no_args).and_return([])

    expect(connection.discover).to eq([])
  end

  it "proves Admin and Data API access for a selected property" do
    allow(admin).to receive(:property_access).with("123456789").and_return(property)
    allow(data).to receive(:run).and_return(
      AnalyticsOps::Reports::Result.new(
        name: "setup_connectivity",
        kind: "standard",
        dimension_headers: ["date"],
        metric_headers: ["activeUsers"],
        rows: [],
        row_count: 0,
        metadata: {}
      )
    )

    verification = connection.verify("123456789")

    expect(verification.property).to eq(property)
    expect(verification.to_h).to include("admin_api" => true, "data_api" => true)
    expect(data).to have_received(:run).with(
      "123456789",
      an_object_having_attributes(name: "setup_connectivity", limit: 1)
    )
  end
end
