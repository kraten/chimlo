import Testing
@testable import ChimloCore

@Suite("Model display names")
struct ModelDisplayNameTests {
    @Test("Claude model versions are derived without a release table", arguments: [
        ("claude-sonnet-5-20260701", "Sonnet 5"),
        ("us.anthropic.claude-fable-5-20260701-v1:0", "Fable 5"),
        ("claude-opus-4-8-20250514", "Opus 4.8"),
        ("claude-haiku-4-5@20251001", "Haiku 4.5"),
        ("claude-3-5-sonnet-20241022", "Sonnet 3.5"),
    ])
    func claudeNames(modelID: String, expected: String) {
        #expect(ModelDisplayName.resolve(modelID: modelID, agent: .claude) == expected)
    }

    @Test("Codex model families are compact beside the provider badge", arguments: [
        ("gpt-5.6-sol", "5.6 Sol"),
        ("gpt-5.6-terra", "5.6 Terra"),
        ("gpt-5.6-luna", "5.6 Luna"),
        ("gpt-5.5", "5.5"),
        ("gpt-5.4-mini", "5.4 Mini"),
        ("gpt-5.3-codex-spark", "5.3 Codex Spark"),
    ])
    func codexNames(modelID: String, expected: String) {
        #expect(ModelDisplayName.resolve(modelID: modelID, agent: .codex) == expected)
    }

    @Test("The provider catalog wins while keeping the compact row treatment")
    func providerCatalogName() {
        #expect(ModelDisplayName.resolve(
            modelID: "gpt-5.6-sol",
            agent: .codex,
            providerDisplayName: "GPT-5.6-Sol"
        ) == "5.6 Sol")
    }

    @Test("Unknown provider model identifiers remain unchanged")
    func unknownModelName() {
        #expect(ModelDisplayName.resolve(
            modelID: "company/custom-model-v2",
            agent: .other
        ) == "company/custom-model-v2")
    }
}
