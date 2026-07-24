# frozen_string_literal: true

RSpec.describe AnalyticsOps::Redaction do
  it "redacts bearer tokens, secret assignments, and private keys" do
    source = <<~TEXT
      authorization: Basic abc.def.secret
      access_token=token-value
      client_secret: "hidden value with spaces"
      client_id: public-but-credential-shaped
      {"refreshToken":"json-secret-value"}
      -----BEGIN PRIVATE KEY-----
      definitely-not-a-real-key
      -----END PRIVATE KEY-----
    TEXT

    redacted = described_class.message(source)

    expect(redacted).not_to include(
      "abc.def.secret",
      "token-value",
      "hidden-value",
      "hidden value with spaces",
      "public-but-credential-shaped",
      "json-secret-value",
      "definitely-not-a-real-key"
    )
    expect(redacted).to include("[REDACTED]")
  end

  it "removes terminal control characters and bounds output" do
    result = described_class.message("safe\u0000\n\r\t\u001f#{"x" * 2_000}")

    expect(result).not_to match(/[\u0000-\u001f\u007f]/)
    expect(result.length).to eq(1_000)
  end

  it "safely replaces invalid byte sequences" do
    invalid = "bad\xFFvalue".dup.force_encoding(Encoding::UTF_8)

    expect(described_class.message(invalid)).to eq("bad?value")
  end

  it "can safely render complete trusted operational text without truncating it" do
    source = "#{"x" * 1_100}VISIBLE-END"

    expect(described_class.text(source)).to end_with("VISIBLE-END")
    expect(described_class.text("access_token=secret")).to eq("access_token=[REDACTED]")
  end
end
