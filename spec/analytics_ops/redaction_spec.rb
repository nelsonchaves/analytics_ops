# frozen_string_literal: true

RSpec.describe AnalyticsOps::Redaction do
  it "redacts bearer tokens, secret assignments, and private keys" do
    source = <<~TEXT
      authorization: Basic abc.def.secret
      access_token=token-value
      client_secret: hidden-value
      client_id: public-but-credential-shaped
      -----BEGIN PRIVATE KEY-----
      definitely-not-a-real-key
      -----END PRIVATE KEY-----
    TEXT

    redacted = described_class.message(source)

    expect(redacted).not_to include(
      "abc.def.secret",
      "token-value",
      "hidden-value",
      "public-but-credential-shaped",
      "definitely-not-a-real-key"
    )
    expect(redacted).to include("[REDACTED]")
  end

  it "removes terminal control characters and bounds output" do
    result = described_class.message("safe\u0000\u001f#{"x" * 2_000}")

    expect(result).not_to match(/[\u0000-\u001f\u007f]/)
    expect(result.length).to eq(1_000)
  end
end
