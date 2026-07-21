import Foundation

/// Produces a compact provider-facing model name without baking current model
/// versions into Chimlo. Provider catalogs can supply a preferred name; model
/// identifiers remain a future-proof fallback for providers without a catalog.
public enum ModelDisplayName {
    public static func resolve(
        modelID: String?,
        agent: AgentKind,
        providerDisplayName: String? = nil
    ) -> String? {
        let candidates = [providerDisplayName, modelID].compactMap(cleaned)
        guard !candidates.isEmpty else { return nil }

        for candidate in candidates {
            let formatted: String?
            switch agent {
            case .claude:
                formatted = formatClaude(candidate)
            case .codex:
                formatted = formatCodex(candidate)
            case .gemini, .cursor, .openCode, .hermes, .other:
                formatted = nil
            }
            if let formatted { return formatted }
        }

        return candidates[0]
    }

    private static func formatClaude(_ source: String) -> String? {
        let lowercased = source.lowercased()
        let modelPortion: Substring
        if let claudeRange = lowercased.range(of: "claude") {
            let offset = lowercased.distance(from: lowercased.startIndex, to: claudeRange.upperBound)
            let sourceIndex = source.index(source.startIndex, offsetBy: offset)
            modelPortion = source[sourceIndex...]
        } else if !source.contains("/") {
            modelPortion = source[...]
        } else {
            return nil
        }

        let beforeProviderVersion = modelPortion.split(separator: "@", maxSplits: 1)[0]
        var tokens = tokenize(beforeProviderVersion)
        tokens.removeAll(where: isReleaseSuffix)
        guard !tokens.isEmpty else { return nil }

        let leadingVersionCount = tokens.prefix(while: isVersionToken).count
        let familyTokens: ArraySlice<String>
        let versionTokens: ArraySlice<String>
        if leadingVersionCount > 0, leadingVersionCount < tokens.count {
            versionTokens = tokens.prefix(leadingVersionCount)
            familyTokens = tokens.dropFirst(leadingVersionCount)
        } else if let versionIndex = tokens.firstIndex(where: isVersionToken) {
            familyTokens = tokens[..<versionIndex]
            versionTokens = tokens[versionIndex...]
        } else {
            familyTokens = tokens[...]
            versionTokens = []
        }

        guard !familyTokens.isEmpty else { return nil }
        let family = familyTokens.map(titleCased).joined(separator: " ")
        let version = versionTokens.map(normalizedVersionToken).joined(separator: ".")
        return version.isEmpty ? family : "\(family) \(version)"
    }

    private static func formatCodex(_ source: String) -> String? {
        let lowercased = source.lowercased()
        let modelPortion: Substring
        if let gptRange = lowercased.range(of: "gpt-") {
            let offset = lowercased.distance(from: lowercased.startIndex, to: gptRange.upperBound)
            let sourceIndex = source.index(source.startIndex, offsetBy: offset)
            modelPortion = source[sourceIndex...]
        } else if lowercased.hasPrefix("codex-")
                    || lowercased.hasPrefix("codex ")
                    || lowercased.first == "o" && lowercased.dropFirst().first?.isNumber == true {
            modelPortion = source[...]
        } else {
            return nil
        }

        let tokens = tokenize(modelPortion).filter { !isReleaseSuffix($0) }
        guard !tokens.isEmpty else { return nil }
        return tokens.map { token in
            isVersionToken(token) ? normalizedVersionToken(token) : titleCased(token)
        }.joined(separator: " ")
    }

    private static func tokenize(_ source: Substring) -> [String] {
        source.split { character in
            character == "-" || character == "_" || character.isWhitespace
        }.map(String.init)
    }

    private static func isVersionToken(_ token: String) -> Bool {
        guard token.contains(where: \.isNumber) else { return false }
        return token.allSatisfy { $0.isNumber || $0 == "." }
    }

    private static func normalizedVersionToken(_ token: String) -> String {
        token.trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }

    private static func isReleaseSuffix(_ token: String) -> Bool {
        let lowercased = token.lowercased()
        if lowercased == "latest" { return true }
        if lowercased.count == 8, lowercased.allSatisfy(\.isNumber) { return true }
        if lowercased.first == "v" {
            let version = lowercased.dropFirst().split(separator: ":", maxSplits: 1)[0]
            return !version.isEmpty && version.allSatisfy(\.isNumber)
        }
        return false
    }

    private static func titleCased(_ token: String) -> String {
        guard let first = token.first else { return token }
        return first.uppercased() + token.dropFirst().lowercased()
    }

    private static func cleaned(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
