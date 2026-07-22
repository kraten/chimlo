import Foundation
import Testing
@testable import ChimloCore

@Suite("Claude status-line configuration")
struct ClaudeStatusLineConfigurationTests {
    private let wrapperPath = "/Users/me/Library/Application Support/Chimlo/bin/chimlo-claude-statusline"

    @Test("Installation preserves an existing status line")
    func preservesExistingStatusLine() throws {
        let existing = Data(#"{"theme":"dark","statusLine":{"type":"command","command":"my-status","padding":2}}"#.utf8)
        let plan = try ClaudeStatusLineConfiguration.merging(
            existingData: existing,
            wrapperPath: wrapperPath
        )

        #expect(try ClaudeStatusLineConfiguration.installationState(
            in: plan.data,
            wrapperPath: wrapperPath
        ) == .current)
        #expect(try ClaudeStatusLineConfiguration.originalCommand(in: plan.data) == "my-status")

        let removed = try ClaudeStatusLineConfiguration.removing(existingData: plan.data)
        let root = try #require(JSONSerialization.jsonObject(with: removed.data) as? [String: Any])
        let restored = try #require(root["statusLine"] as? [String: Any])
        #expect(restored["command"] as? String == "my-status")
        #expect((restored["padding"] as? NSNumber)?.intValue == 2)
        #expect(root[ClaudeStatusLineConfiguration.managedKey] == nil)
    }

    @Test("Installation without a prior status line removes cleanly")
    func noPriorStatusLine() throws {
        let plan = try ClaudeStatusLineConfiguration.merging(
            existingData: Data(#"{"theme":"dark"}"#.utf8),
            wrapperPath: wrapperPath
        )
        let repeated = try ClaudeStatusLineConfiguration.merging(
            existingData: plan.data,
            wrapperPath: wrapperPath
        )
        #expect(!repeated.changed)

        let removed = try ClaudeStatusLineConfiguration.removing(existingData: plan.data)
        let root = try #require(JSONSerialization.jsonObject(with: removed.data) as? [String: Any])
        #expect(root["statusLine"] == nil)
        #expect(root["theme"] as? String == "dark")
    }

    @Test("An existing Claude connection gains the capacity bridge")
    func upgradesConnectedInstallation() throws {
        let helperPath = "/Users/me/Library/Application Support/Chimlo/bin/chimlo"
        let existing = Data(
            #"{"statusLine":{"type":"command","command":"/Users/me/.vibe-island/bin/vibe-island-statusline"}}"#.utf8
        )
        let connected = try ClaudeHookConfiguration.merging(
            existingData: existing,
            helperPath: helperPath
        ).data

        let plan = try #require(try ClaudeStatusLineConfiguration.upgradingConnectedInstallation(
            existingData: connected,
            helperPath: helperPath,
            wrapperPath: wrapperPath
        ))

        #expect(plan.changed)
        #expect(try ClaudeStatusLineConfiguration.installationState(
            in: plan.data,
            wrapperPath: wrapperPath
        ) == .current)
        #expect(
            try ClaudeStatusLineConfiguration.originalCommand(in: plan.data)
                == "/Users/me/.vibe-island/bin/vibe-island-statusline"
        )
    }

    @Test("An unconnected Claude installation is never upgraded automatically")
    func doesNotUpgradeDisconnectedInstallation() throws {
        let existing = Data(
            #"{"statusLine":{"type":"command","command":"my-status"}}"#.utf8
        )

        #expect(try ClaudeStatusLineConfiguration.upgradingConnectedInstallation(
            existingData: existing,
            helperPath: "/Users/me/Library/Application Support/Chimlo/bin/chimlo",
            wrapperPath: wrapperPath
        ) == nil)
    }

    @Test("Repair preserves a status line that replaced Chimlo's wrapper")
    func repairPreservesExternalReplacement() throws {
        let installed = try ClaudeStatusLineConfiguration.merging(
            existingData: Data(
                #"{"statusLine":{"type":"command","command":"old-status"}}"#.utf8
            ),
            wrapperPath: wrapperPath
        )
        var root = try #require(
            JSONSerialization.jsonObject(with: installed.data) as? [String: Any]
        )
        root["statusLine"] = [
            "type": "command",
            "command": "replacement-status",
        ]
        let replaced = try JSONSerialization.data(withJSONObject: root)

        let repaired = try ClaudeStatusLineConfiguration.merging(
            existingData: replaced,
            wrapperPath: wrapperPath
        )

        #expect(
            try ClaudeStatusLineConfiguration.originalCommand(in: repaired.data)
                == "replacement-status"
        )
    }
}
