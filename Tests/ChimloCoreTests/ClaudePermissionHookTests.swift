import Foundation
import Testing
@testable import ChimloCore

@Suite("Claude permission hook")
struct ClaudePermissionHookTests {
    private let payload = Data(
        #"{"session_id":"claude-1","hook_event_name":"PermissionRequest","tool_name":"Write","cwd":"/Users/me/Projects/chimlo","transcript_path":"/private/secret.jsonl","tool_input":{"file_path":"/Users/me/Projects/chimlo/hello.txt","content":"Hello from Chimlo"},"permission_suggestions":[{"type":"setMode","mode":"bypassPermissions","destination":"session"},{"type":"addRules","rules":[{"toolName":"Write","ruleContent":"/Users/me/Projects/chimlo/*"}],"behavior":"allow","destination":"session"}]}"#.utf8
    )

    @Test("Parses a bounded transient permission presentation")
    func parsesPermissionPresentation() throws {
        let hook = try ClaudePermissionHook(data: payload)

        #expect(hook.request.sessionID == "claude-1")
        #expect(hook.request.agent == .claude)
        #expect(hook.request.title == "chimlo")
        #expect(hook.request.toolName == "Write")
        #expect(hook.request.prompt == "Do you want Claude to write hello.txt?")
        #expect(hook.request.detail == "/Users/me/Projects/chimlo/hello.txt")
        #expect(hook.request.preview == "Hello from Chimlo")
        #expect(hook.request.allowsSessionApproval)
    }

    @Test("Allow once grants only the current request")
    func allowsOnce() throws {
        let hook = try ClaudePermissionHook(data: payload)
        let output = hook.output(for: ProviderPermissionResponse(
            requestID: hook.request.id,
            outcome: .allowedOnce
        ))
        let decision = try decision(from: output)

        #expect(decision["behavior"] as? String == "allow")
        #expect(decision["updatedPermissions"] == nil)
    }

    @Test("Allow all echoes only Claude's session allow rule")
    func allowsForSessionWithoutBypass() throws {
        let hook = try ClaudePermissionHook(data: payload)
        let output = hook.output(for: ProviderPermissionResponse(
            requestID: hook.request.id,
            outcome: .allowedForSession
        ))
        let decision = try decision(from: output)
        let updates = try #require(decision["updatedPermissions"] as? [[String: Any]])
        let update = try #require(updates.first)

        #expect(updates.count == 1)
        #expect(update["type"] as? String == "addRules")
        #expect(update["behavior"] as? String == "allow")
        #expect(update["destination"] as? String == "session")
        #expect(String(decoding: output, as: UTF8.self).contains("bypassPermissions") == false)
    }

    @Test("Deny is explicit and does not interrupt Claude")
    func denies() throws {
        let hook = try ClaudePermissionHook(data: payload)
        let output = hook.output(for: ProviderPermissionResponse(
            requestID: hook.request.id,
            outcome: .denied
        ))
        let decision = try decision(from: output)

        #expect(decision["behavior"] as? String == "deny")
        #expect(decision["interrupt"] as? Bool == false)
    }

    @Test("Unavailable and mismatched responses fall back while bypass becomes safe edit mode")
    func invalidResponsesFallBackAndBypassIsIgnored() throws {
        let hook = try ClaudePermissionHook(data: payload)
        #expect(hook.output(for: .unavailable(for: hook.request.id)) == ClaudePermissionHook.fallbackOutput)
        #expect(hook.output(for: ProviderPermissionResponse(
            requestID: UUID(),
            outcome: .allowedOnce
        )) == ClaudePermissionHook.fallbackOutput)

        let bypassOnly = Data(
            #"{"session_id":"claude-1","hook_event_name":"PermissionRequest","tool_name":"Write","tool_input":{"file_path":"hello.txt","content":"hello"},"permission_suggestions":[{"type":"setMode","mode":"bypassPermissions","destination":"session"}]}"#.utf8
        )
        let bypassHook = try ClaudePermissionHook(data: bypassOnly)
        #expect(bypassHook.request.allowsSessionApproval)
        let output = bypassHook.output(for: ProviderPermissionResponse(
            requestID: bypassHook.request.id,
            outcome: .allowedForSession
        ))
        let updateDecision = try decision(from: output)
        let updates = try #require(updateDecision["updatedPermissions"] as? [[String: Any]])
        let update = try #require(updates.first)
        #expect(update["type"] as? String == "setMode")
        #expect(update["mode"] as? String == "acceptEdits")
        #expect(update["destination"] as? String == "session")
        #expect(!String(decoding: output, as: UTF8.self).contains("bypassPermissions"))
    }

    @Test("Canonical Edit suggestions cover Write and are narrowed to the session")
    func canonicalEditSuggestionCoversWrite() throws {
        let input = Data(
            #"{"session_id":"claude-1","hook_event_name":"PermissionRequest","tool_name":"Write","tool_input":{"file_path":"hi.txt","content":"hello"},"permission_suggestions":[{"type":"addRules","rules":[{"toolName":"Edit"}],"behavior":"allow","destination":"localSettings"}]}"#.utf8
        )
        let hook = try ClaudePermissionHook(data: input)
        let output = hook.output(for: ProviderPermissionResponse(
            requestID: hook.request.id,
            outcome: .allowedForSession
        ))
        let updateDecision = try decision(from: output)
        let updates = try #require(updateDecision["updatedPermissions"] as? [[String: Any]])
        let update = try #require(updates.first)
        let rules = try #require(update["rules"] as? [[String: Any]])

        #expect(rules.first?["toolName"] as? String == "Edit")
        #expect(update["destination"] as? String == "session")
    }

    @Test("The asynchronous observer ignores Claude permission events")
    func observerDoesNotRacePermissionBridge() throws {
        #expect(try PrivacySafeHookMapper.event(from: payload, source: .claude) == nil)

        let notification = Data(
            #"{"session_id":"claude-1","hook_event_name":"Notification","notification_type":"permission_prompt","tool_name":"Write"}"#.utf8
        )
        #expect(try PrivacySafeHookMapper.event(from: notification, source: .claude) == nil)
    }

    private func decision(from output: Data) throws -> [String: Any] {
        let root = try #require(JSONSerialization.jsonObject(with: output) as? [String: Any])
        let specific = try #require(root["hookSpecificOutput"] as? [String: Any])
        #expect(specific["hookEventName"] as? String == "PermissionRequest")
        return try #require(specific["decision"] as? [String: Any])
    }
}
