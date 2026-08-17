import Foundation
import XCTest

final class PrivacyContractTests: XCTestCase {
    func testSensitiveSurfacesDoNotReadWindowDescriptorTitles() throws {
        let sources = try productionSources()
        let violations = sources.compactMap { source -> String? in
            let code = strippingComments(from: source.contents)
            let path = source.url.path
            let lowerPath = path.lowercased()
            let sensitivePath = lowerPath.contains("/diagnostic")
                || lowerPath.contains("/menubar")
                || lowerPath.contains("/profile")
                || lowerPath.contains("/preference")
            guard sensitivePath,
                  code.range(of: #"\.\s*title\b"#, options: .regularExpression) != nil else {
                return nil
            }
            return path
        }

        XCTAssertTrue(
            violations.isEmpty,
            "Privacy-sensitive source must not read WindowDescriptor.title: \(violations.joined(separator: ", "))"
        )
    }

    func testLoggerCallsDoNotContainProfileNamesOrWindowLabels() throws {
        let sources = try productionSources()
        var violations: [String] = []

        for source in sources {
            let code = strippingComments(from: source.contents)
            for call in loggerCallBodies(in: code) where loggerCallContainsSensitiveName(call) {
                violations.append("\(source.url.path): \(call.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
        }

        XCTAssertTrue(
            violations.isEmpty,
            "Logger calls must not include profile names or window labels: \(violations.joined(separator: " | "))"
        )
    }

    func testDisplayBindingContainsDisplayIdentityOnly() throws {
        let sources = try productionSources()
        let matches = sources.compactMap { source -> String? in
            let code = strippingComments(from: source.contents)
            guard let declaration = code.range(
                of: #"\bstruct\s+DisplayBinding\b"#,
                options: .regularExpression
            ), let openingBrace = code[declaration.upperBound...].firstIndex(of: "{") else {
                return nil
            }
            guard let body = delimitedBody(in: code, openingAt: openingBrace, opening: "{", closing: "}") else {
                return "\(source.url.path): malformed DisplayBinding declaration"
            }

            let lowerBody = body.lowercased()
            let geometryTerms = [
                "cgrect", "cgpoint", "cgsize", "geometry", "visibleframe",
                "frame", "origin", "bounds", "width", "height"
            ]
            let found = geometryTerms.filter { lowerBody.contains($0) }
            return found.isEmpty ? nil : "\(source.url.path): \(found.joined(separator: ", "))"
        }

        XCTAssertEqual(matches.count, 0, "DisplayBinding must not persist geometry: \(matches.joined(separator: " | "))")
        XCTAssertTrue(
            sources.contains { source in
                strippingComments(from: source.contents).range(
                    of: #"\bstruct\s+DisplayBinding\b"#,
                    options: .regularExpression
                ) != nil
            },
            "The DisplayBinding contract must remain present in production source"
        )
    }

    private struct SourceFile {
        let url: URL
        let contents: String
    }

    private enum RootResolutionError: Error {
        case repositoryRootNotFound
    }

    private func productionSources() throws -> [SourceFile] {
        let root = try repositoryRoot()
        let sourceRoot = root.appendingPathComponent("Sources/Schiera", isDirectory: true)
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: sourceRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return try enumerator.compactMap { item -> SourceFile? in
            guard let url = item as? URL, url.pathExtension == "swift" else { return nil }
            return SourceFile(url: url, contents: try String(contentsOf: url, encoding: .utf8))
        }.sorted { $0.url.path < $1.url.path }
    }

    private func repositoryRoot() throws -> URL {
        let fileManager = FileManager.default
        var candidate = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while true {
            let sourcePath = candidate.appendingPathComponent("Sources/Schiera", isDirectory: true).path
            if fileManager.fileExists(atPath: sourcePath) {
                return candidate
            }
            let parent = candidate.deletingLastPathComponent()
            guard parent.path != candidate.path else { break }
            candidate = parent
        }

        candidate = URL(fileURLWithPath: fileManager.currentDirectoryPath)
        while true {
            let sourcePath = candidate.appendingPathComponent("Sources/Schiera", isDirectory: true).path
            if fileManager.fileExists(atPath: sourcePath) {
                return candidate
            }
            let parent = candidate.deletingLastPathComponent()
            guard parent.path != candidate.path else { break }
            candidate = parent
        }
        throw RootResolutionError.repositoryRootNotFound
    }

    private func strippingComments(from source: String) -> String {
        var result = ""
        var index = source.startIndex
        var inString = false
        var escaped = false
        var blockCommentDepth = 0

        while index < source.endIndex {
            let next = source.index(after: index)
            let character = source[index]
            let nextCharacter = next < source.endIndex ? source[next] : nil

            if blockCommentDepth > 0 {
                if character == "/", nextCharacter == "*" {
                    blockCommentDepth += 1
                    index = source.index(after: next)
                } else if character == "*", nextCharacter == "/" {
                    blockCommentDepth -= 1
                    index = source.index(after: next)
                } else {
                    if character.isNewline { result.append(character) }
                    index = next
                }
                continue
            }

            if inString {
                result.append(character)
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
                index = next
                continue
            }

            if character == "/", nextCharacter == "/" {
                index = source.index(after: next)
                while index < source.endIndex, !source[index].isNewline {
                    index = source.index(after: index)
                }
                continue
            }
            if character == "/", nextCharacter == "*" {
                blockCommentDepth = 1
                index = source.index(after: next)
                continue
            }
            if character == "\"" {
                inString = true
            }
            result.append(character)
            index = next
        }
        return result
    }

    private func loggerCallBodies(in source: String) -> [String] {
        let pattern = #"\b(?:logger|Logger)\s*(?:\.\s*(?:debug|error|fault|info|log|notice|trace|warning))?\s*\("#
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }

        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        return expression.matches(in: source, range: range).compactMap { match in
            let openingOffset = match.range.location + match.range.length - 1
            let opening = String.Index(utf16Offset: openingOffset, in: source)
            guard let body = delimitedBody(in: source, openingAt: opening, opening: "(", closing: ")") else {
                return nil
            }
            return body
        }
    }

    private func loggerCallContainsSensitiveName(_ body: String) -> Bool {
        let directPropertyPatterns = [
            #"\b(?:profile|arrangementProfile|selectedProfile)\s*\.\s*(?:name|displayName|label)\b"#,
            #"\b(?:window|windowDescriptor|focusedWindow|selectedWindow|windowChoice)\s*\.\s*(?:title|label|name)\b"#,
            #"\b(?:profileName|profileLabel|windowTitle|windowLabel|windowName|label|title)\b"#,
            #"\.\s*(?:title|label)\b"#
        ]
        return directPropertyPatterns.contains {
            body.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil
        }
    }

    private func delimitedBody(
        in source: String,
        openingAt start: String.Index,
        opening delimiter: Character,
        closing: Character
    ) -> String? {
        var depth = 0
        var index = start
        var inString = false
        var escaped = false

        while index < source.endIndex {
            let character = source[index]
            if inString {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
            } else if character == "\"" {
                inString = true
            } else if character == delimiter {
                depth += 1
            } else if character == closing {
                depth -= 1
                if depth == 0 {
                    let bodyStart = source.index(after: start)
                    return String(source[bodyStart..<index])
                }
            }
            index = source.index(after: index)
        }
        return nil
    }
}
