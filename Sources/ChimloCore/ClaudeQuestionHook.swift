import Foundation

public enum ClaudeQuestionHookError: Error, LocalizedError, Sendable {
    case payloadTooLarge
    case malformedPayload
    case unsupportedEvent
    case invalidQuestion

    public var errorDescription: String? {
        switch self {
        case .payloadTooLarge: "Claude question payload exceeds the local safety limit"
        case .malformedPayload: "Claude question payload is not valid JSON"
        case .unsupportedEvent: "Claude hook is not an AskUserQuestion event"
        case .invalidQuestion: "Claude question payload is incomplete or out of bounds"
        }
    }
}

/// Parses Claude Code's AskUserQuestion hook without retaining transcript or
/// tool context. The original question array is held only for this blocking
/// hook invocation so the answer can be echoed back in `updatedInput`.
public struct ClaudeQuestionHook: Sendable {
    public static let maximumPayloadBytes = 64 * 1_024
    public static let fallbackOutput = Data("{}\n".utf8)

    public let request: ProviderQuestionRequest
    private let originalQuestionsJSON: Data

    public init(data: Data, expiresAt: Date? = nil) throws {
        guard data.count <= Self.maximumPayloadBytes else {
            throw ClaudeQuestionHookError.payloadTooLarge
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let eventName = root["hook_event_name"] as? String,
              let toolName = root["tool_name"] as? String else {
            throw ClaudeQuestionHookError.malformedPayload
        }
        guard eventName == "PreToolUse", toolName == "AskUserQuestion" else {
            throw ClaudeQuestionHookError.unsupportedEvent
        }
        guard let rawSessionID = Self.boundedString(root["session_id"], maximumBytes: 512),
              let toolInput = root["tool_input"] as? [String: Any],
              let rawQuestions = toolInput["questions"] as? [[String: Any]],
              (1...4).contains(rawQuestions.count) else {
            throw ClaudeQuestionHookError.invalidQuestion
        }
        let sessionID = rawSessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sessionID.isEmpty else { throw ClaudeQuestionHookError.invalidQuestion }

        var seenPrompts = Set<String>()
        let questions = try rawQuestions.map { raw -> ProviderQuestion in
            guard let prompt = Self.boundedString(raw["question"], maximumBytes: 2_048),
                  seenPrompts.insert(prompt).inserted,
                  let rawOptions = raw["options"] as? [[String: Any]],
                  (2...4).contains(rawOptions.count) else {
                throw ClaudeQuestionHookError.invalidQuestion
            }
            let options = try rawOptions.map { rawOption -> ProviderQuestionOption in
                guard let label = Self.boundedString(rawOption["label"], maximumBytes: 256) else {
                    throw ClaudeQuestionHookError.invalidQuestion
                }
                let detail = Self.optionalBoundedString(rawOption["description"], maximumBytes: 1_024)
                return ProviderQuestionOption(label: label, detail: detail)
            }
            guard Set(options.map(\.label)).count == options.count else {
                throw ClaudeQuestionHookError.invalidQuestion
            }
            return ProviderQuestion(
                prompt: prompt,
                header: Self.optionalBoundedString(raw["header"], maximumBytes: 128),
                options: options,
                allowsMultipleSelections: raw["multiSelect"] as? Bool ?? false
            )
        }

        let cwd = Self.optionalBoundedString(root["cwd"], maximumBytes: 4_096)
        let projectName = cwd.map { URL(fileURLWithPath: $0).lastPathComponent }
            .flatMap { $0.isEmpty ? nil : $0 }
        request = ProviderQuestionRequest(
            sessionID: sessionID,
            agent: .claude,
            title: projectName ?? "Claude Code session",
            questions: questions,
            expiresAt: expiresAt
        )
        originalQuestionsJSON = try JSONSerialization.data(withJSONObject: rawQuestions)
    }

    public func output(for response: ProviderQuestionResponse) -> Data {
        guard response.requestID == request.id,
              response.outcome == .answered,
              response.answers.count == request.questions.count,
              request.questions.allSatisfy({ question in
                  guard let answer = response.answers[question.prompt] else { return false }
                  let labels = question.options.map(\.label)
                  if question.allowsMultipleSelections {
                      let selections = answer.components(separatedBy: ", ")
                      return !selections.isEmpty
                          && Set(selections).count == selections.count
                          && selections.allSatisfy(labels.contains)
                  }
                  return labels.contains(answer)
              }),
              let originalQuestions = try? JSONSerialization.jsonObject(with: originalQuestionsJSON)
        else { return Self.fallbackOutput }

        let output: [String: Any] = [
            "hookSpecificOutput": [
                "hookEventName": "PreToolUse",
                "permissionDecision": "allow",
                "permissionDecisionReason": "Answered in Chimlo",
                "updatedInput": [
                    "questions": originalQuestions,
                    "answers": response.answers,
                ],
            ],
        ]
        guard let data = try? JSONSerialization.data(
            withJSONObject: output,
            options: [.sortedKeys, .withoutEscapingSlashes]
        ) else { return Self.fallbackOutput }
        return data + Data("\n".utf8)
    }

    private static func boundedString(_ value: Any?, maximumBytes: Int) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.utf8.count <= maximumBytes else { return nil }
        return value
    }

    private static func optionalBoundedString(_ value: Any?, maximumBytes: Int) -> String? {
        guard value != nil else { return nil }
        return boundedString(value, maximumBytes: maximumBytes)
    }
}
