import Foundation
import Testing
@testable import ChimloCore

@Suite("Codex hook configuration")
struct HookConfigurationTests {
    private let helperPath = "/Applications/Chimlo.app/Contents/Helpers/chimlo"

    @Test("Merge preserves unrelated hooks and becomes current")
    func mergePreservesUnrelatedHooks() throws {
        let existing = Data(#"{"description":"keep me","hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"existing-observer"}]}],"Unrelated":[{"hooks":[{"type":"command","command":"leave-this-alone"}]}]}}"#.utf8)

        let plan = try CodexHookConfiguration.merging(existingData: existing, helperPath: helperPath)
        #expect(plan.changed)
        #expect(try CodexHookConfiguration.installationState(in: plan.data, helperPath: helperPath) == .current)

        let root = try #require(JSONSerialization.jsonObject(with: plan.data) as? [String: Any])
        #expect(root["description"] as? String == "keep me")
        let hooks = try #require(root["hooks"] as? [String: Any])
        let unrelated = try #require(hooks["Unrelated"] as? [[String: Any]])
        let observers = try #require(unrelated.first?["hooks"] as? [[String: Any]])
        #expect(observers.first?["command"] as? String == "leave-this-alone")
    }

    @Test("Merge is idempotent")
    func mergeIsIdempotent() throws {
        let first = try CodexHookConfiguration.merging(existingData: nil, helperPath: helperPath)
        let second = try CodexHookConfiguration.merging(existingData: first.data, helperPath: helperPath)
        #expect(first.changed)
        #expect(!second.changed)
        #expect(first.data == second.data)
    }

    @Test("Moving the app produces a repair plan")
    func movedHelperNeedsRepair() throws {
        let oldPath = "/tmp/Chimlo.app/Contents/Helpers/chimlo"
        let installed = try CodexHookConfiguration.merging(existingData: nil, helperPath: oldPath)
        #expect(try CodexHookConfiguration.installationState(in: installed.data, helperPath: helperPath) == .needsRepair)

        let repaired = try CodexHookConfiguration.merging(existingData: installed.data, helperPath: helperPath)
        #expect(repaired.changed)
        #expect(try CodexHookConfiguration.installationState(in: repaired.data, helperPath: helperPath) == .current)
        #expect(!String(decoding: repaired.data, as: UTF8.self).contains(oldPath))
    }

    @Test("Removal is marker scoped")
    func removalIsMarkerScoped() throws {
        let existing = Data(#"{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"existing-observer"}]}]}}"#.utf8)
        let installed = try CodexHookConfiguration.merging(existingData: existing, helperPath: helperPath)
        let removed = try CodexHookConfiguration.removing(existingData: installed.data)

        #expect(removed.changed)
        #expect(try CodexHookConfiguration.installationState(in: removed.data, helperPath: helperPath) == .missing)
        let text = String(decoding: removed.data, as: UTF8.self)
        #expect(text.contains("existing-observer"))
        #expect(!text.contains(CodexHookConfiguration.marker))
    }
}

@Suite("Claude hook configuration")
struct ClaudeHookConfigurationTests {
    private let helperPath = "/Users/me/Library/Application Support/Chimlo/bin/chimlo"

    @Test("Merge preserves unrelated Claude settings and hooks")
    func mergePreservesUnrelatedSettings() throws {
        let existing = Data(#"{"theme":"dark","hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"my-observer"}]}],"Unrelated":[{"hooks":[{"type":"command","command":"leave-this-alone"}]}]}}"#.utf8)
        let plan = try ClaudeHookConfiguration.merging(existingData: existing, helperPath: helperPath)

        #expect(plan.changed)
        #expect(try ClaudeHookConfiguration.installationState(in: plan.data, helperPath: helperPath) == .current)
        let root = try #require(JSONSerialization.jsonObject(with: plan.data) as? [String: Any])
        #expect(root["theme"] as? String == "dark")
        let text = String(decoding: plan.data, as: UTF8.self)
        #expect(text.contains("my-observer"))
        #expect(text.contains("leave-this-alone"))
        #expect(text.contains(ClaudeHookConfiguration.questionMarker))
        #expect(text.contains("AskUserQuestion"))
        #expect(text.contains(ClaudeHookConfiguration.permissionMarker))
        #expect(text.contains("hook claude permission"))
        #expect(text.contains("\"timeout\" : 600"))
    }

    @Test("Claude merge is idempotent and removal is marker scoped")
    func mergeAndRemove() throws {
        let first = try ClaudeHookConfiguration.merging(existingData: nil, helperPath: helperPath)
        let second = try ClaudeHookConfiguration.merging(existingData: first.data, helperPath: helperPath)
        #expect(!second.changed)
        #expect(second.data == first.data)

        let removed = try ClaudeHookConfiguration.removing(existingData: first.data)
        #expect(removed.changed)
        #expect(try ClaudeHookConfiguration.installationState(in: removed.data, helperPath: helperPath) == .missing)
        #expect(!String(decoding: removed.data, as: UTF8.self).contains(ClaudeHookConfiguration.marker))
        #expect(!String(decoding: removed.data, as: UTF8.self).contains(ClaudeHookConfiguration.questionMarker))
        #expect(!String(decoding: removed.data, as: UTF8.self).contains(ClaudeHookConfiguration.permissionMarker))
    }

    @Test("A non-blocking or broad question hook requires repair")
    func unsafeQuestionRegistrationNeedsRepair() throws {
        let installed = try ClaudeHookConfiguration.merging(
            existingData: nil,
            helperPath: helperPath
        )
        var root = try #require(JSONSerialization.jsonObject(with: installed.data) as? [String: Any])
        var hooks = try #require(root["hooks"] as? [String: Any])
        var preToolUse = try #require(hooks["PreToolUse"] as? [[String: Any]])
        let questionIndex = try #require(preToolUse.firstIndex { group in
            let commands = (group["hooks"] as? [[String: Any]] ?? [])
                .compactMap { $0["command"] as? String }
            return commands.contains(where: { $0.contains(ClaudeHookConfiguration.questionMarker) })
        })
        preToolUse[questionIndex]["matcher"] = "*"
        var questionHooks = try #require(preToolUse[questionIndex]["hooks"] as? [[String: Any]])
        questionHooks[0]["async"] = true
        preToolUse[questionIndex]["hooks"] = questionHooks
        hooks["PreToolUse"] = preToolUse
        root["hooks"] = hooks
        let unsafe = try JSONSerialization.data(withJSONObject: root)

        #expect(try ClaudeHookConfiguration.installationState(
            in: unsafe,
            helperPath: helperPath
        ) == .needsRepair)
        let repaired = try ClaudeHookConfiguration.merging(
            existingData: unsafe,
            helperPath: helperPath
        )
        #expect(repaired.changed)
        #expect(try ClaudeHookConfiguration.installationState(
            in: repaired.data,
            helperPath: helperPath
        ) == .current)
    }

    @Test("A non-blocking Claude permission hook requires repair")
    func unsafePermissionRegistrationNeedsRepair() throws {
        let installed = try ClaudeHookConfiguration.merging(
            existingData: nil,
            helperPath: helperPath
        )
        var root = try #require(JSONSerialization.jsonObject(with: installed.data) as? [String: Any])
        var hooks = try #require(root["hooks"] as? [String: Any])
        var groups = try #require(hooks["PermissionRequest"] as? [[String: Any]])
        let index = try #require(groups.firstIndex { group in
            let commands = (group["hooks"] as? [[String: Any]] ?? [])
                .compactMap { $0["command"] as? String }
            return commands.contains(where: { $0.contains(ClaudeHookConfiguration.permissionMarker) })
        })
        var handlers = try #require(groups[index]["hooks"] as? [[String: Any]])
        handlers[0]["async"] = true
        groups[index]["hooks"] = handlers
        hooks["PermissionRequest"] = groups
        root["hooks"] = hooks
        let unsafe = try JSONSerialization.data(withJSONObject: root)

        #expect(try ClaudeHookConfiguration.installationState(
            in: unsafe,
            helperPath: helperPath
        ) == .needsRepair)
        let repaired = try ClaudeHookConfiguration.merging(
            existingData: unsafe,
            helperPath: helperPath
        )
        #expect(try ClaudeHookConfiguration.installationState(
            in: repaired.data,
            helperPath: helperPath
        ) == .current)
    }

    @Test("Repair replaces the legacy asynchronous permission observer")
    func legacyPermissionObserverIsReplaced() throws {
        let legacyCommand = ClaudeHookConfiguration.observerCommand(helperPath: helperPath)
        let legacy = Data(
            #"{"hooks":{"PermissionRequest":[{"matcher":"*","hooks":[{"type":"command","command":"\#(legacyCommand)","async":true,"timeout":2}]}]}}"#.utf8
        )

        #expect(try ClaudeHookConfiguration.installationState(
            in: legacy,
            helperPath: helperPath
        ) == .needsRepair)
        let repaired = try ClaudeHookConfiguration.merging(
            existingData: legacy,
            helperPath: helperPath
        )
        let root = try #require(JSONSerialization.jsonObject(with: repaired.data) as? [String: Any])
        let hooks = try #require(root["hooks"] as? [String: Any])
        let groups = try #require(hooks["PermissionRequest"] as? [[String: Any]])
        let commands = groups.flatMap { group in
            (group["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String }
        }

        #expect(try ClaudeHookConfiguration.installationState(
            in: repaired.data,
            helperPath: helperPath
        ) == .current)
        #expect(commands.contains(where: { $0.contains(ClaudeHookConfiguration.permissionMarker) }))
        #expect(!commands.contains(where: { $0.contains(ClaudeHookConfiguration.marker) }))
    }
}
