import Foundation

public struct DemoBeat: Codable, Equatable, Sendable {
    public let offsetMilliseconds: Int
    public let event: AgentEvent

    public init(offsetMilliseconds: Int, event: AgentEvent) {
        self.offsetMilliseconds = offsetMilliseconds
        self.event = event
    }
}

public enum DemoScript {
    public static func make(start: Date = Date(timeIntervalSince1970: 1_785_000_000)) -> [DemoBeat] {
        let sessionID = "chimlo-demo-lighthouse"
        let approval = PendingRequest.approval(
            ApprovalRequest(
                id: "demo-check",
                summary: "Run the focused lighthouse checks?",
                detail: "swift test --filter LighthouseTests"
            )
        )

        return [
            DemoBeat(
                offsetMilliseconds: 0,
                event: AgentEvent(
                    id: fixedUUID(1),
                    sessionID: sessionID,
                    sequence: 1,
                    kind: .sessionStarted,
                    agent: .codex,
                    title: "Fix the tiny lighthouse",
                    detail: "Reading the signal controller",
                    terminal: "Terminal",
                    timestamp: start
                )
            ),
            DemoBeat(
                offsetMilliseconds: 900,
                event: AgentEvent(
                    id: fixedUUID(2),
                    sessionID: sessionID,
                    sequence: 2,
                    kind: .activity,
                    agent: .codex,
                    detail: "Editing the blink cadence",
                    timestamp: start.addingTimeInterval(0.9)
                )
            ),
            DemoBeat(
                offsetMilliseconds: 1_800,
                event: AgentEvent(
                    id: fixedUUID(3),
                    sessionID: sessionID,
                    sequence: 3,
                    kind: .permissionRequested,
                    agent: .codex,
                    detail: "Waiting for your decision",
                    request: approval,
                    timestamp: start.addingTimeInterval(1.8)
                )
            ),
            DemoBeat(
                offsetMilliseconds: 3_200,
                event: AgentEvent(
                    id: fixedUUID(4),
                    sessionID: sessionID,
                    sequence: 4,
                    kind: .permissionResolved,
                    agent: .codex,
                    detail: "Running three focused checks",
                    decision: .allow,
                    timestamp: start.addingTimeInterval(3.2)
                )
            ),
            DemoBeat(
                offsetMilliseconds: 4_200,
                event: AgentEvent(
                    id: fixedUUID(5),
                    sessionID: sessionID,
                    sequence: 5,
                    kind: .completed,
                    agent: .codex,
                    detail: "Three checks passed",
                    timestamp: start.addingTimeInterval(4.2)
                )
            ),
        ]
    }

    private static func fixedUUID(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
    }
}
