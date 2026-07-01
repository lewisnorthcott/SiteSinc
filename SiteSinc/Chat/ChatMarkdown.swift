import SwiftUI

/// Renders assistant chat content as an `AttributedString`, turning inline
/// `[Source N]` markers into tappable links (mirroring the web app's
/// `assistantContentToMarkdown` + `AssistantMessageMarkdown`).
enum ChatMarkdown {
    /// Scheme used for synthetic citation links so we can intercept taps via `openURL`
    /// instead of navigating to a real URL.
    static let citationScheme = "sitesinc-citation"

    /// Strips the "Sources: [Source X] (...)" footer some assistant replies append,
    /// and any leftover bracketed source tags once citations are inlined as links.
    private static func stripSourceFooter(_ content: String) -> String {
        let pattern = #"Sources:\s*(\[Source\s+\d+\][^;]*;?\s*)*"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return content
        }
        let range = NSRange(location: 0, length: (content as NSString).length)
        let cleaned = regex.stringByReplacingMatches(in: content, options: [], range: range, withTemplate: "")
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Replaces `[Source N]` with a markdown link to `sitesinc-citation://N` when a
    /// matching citation is known; otherwise strips the bracketed tag.
    private static func inlineCitationLinks(in text: String, citations: [String: ChatCitationRecord]) -> String {
        guard !citations.isEmpty else {
            return text.replacingOccurrences(of: #"\[Sources?\s*[^\]]*\]"#, with: "", options: .regularExpression)
        }

        let pattern = #"\[Source (\d+)\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let nsRange = NSRange(location: 0, length: (text as NSString).length)
        let matches = regex.matches(in: text, range: nsRange)

        var result = text
        for match in matches.reversed() {
            guard let numberRange = Range(match.range(at: 1), in: text),
                  let fullRange = Range(match.range, in: result) else { continue }
            let number = String(text[numberRange])
            guard let citation = citations[number] else {
                result.replaceSubrange(fullRange, with: "")
                continue
            }
            let label = citation.label.replacingOccurrences(of: "]", with: "")
            let replacement = "[\(label)](\(citationScheme)://\(number))"
            result.replaceSubrange(fullRange, with: replacement)
        }

        // Any grouped tags like "[Sources 2-4]" that weren't individually expanded.
        result = result.replacingOccurrences(of: #"\[Sources?\s*[^\]]*\]"#, with: "", options: .regularExpression)
        return result
    }

    /// Builds a styled `AttributedString` ready for display in a SwiftUI `Text`.
    static func attributedString(
        from rawContent: String,
        citations: [String: ChatCitationRecord]?
    ) -> AttributedString {
        var text = stripSourceFooter(rawContent)
        text = inlineCitationLinks(in: text, citations: citations ?? [:])

        guard var attributed = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .full)
        ) else {
            return AttributedString(text)
        }

        // Collect ranges first — mutating `attributed` while iterating its own
        // `runs` view can invalidate the sequence mid-iteration.
        let linkRanges = attributed.runs.filter { $0.link != nil }.map(\.range)
        for range in linkRanges {
            attributed[range].foregroundColor = ChatTheme.purple
            attributed[range].underlineStyle = .single
            attributed[range].font = .system(size: 15, weight: .semibold)
        }
        return attributed
    }

    /// Extracts the citation number from a `sitesinc-citation://N` link, if applicable.
    static func citationNumber(from url: URL) -> String? {
        guard url.scheme == citationScheme else { return nil }
        return url.host
    }
}
