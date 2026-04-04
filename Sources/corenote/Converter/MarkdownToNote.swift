import Foundation

// MARK: - MarkdownToNote

enum MarkdownToNote: Sendable {

    /// Converts a Markdown string into a `DecodedNoteBody`.
    static func convert(_ markdown: String) -> DecodedNoteBody {
        let lines = markdown.components(separatedBy: "\n")
        var allText = ""
        var allRuns: [DecodedRun] = []

        for line in lines {
            // Parse the line into paragraph style + inline segments
            let (paragraphStyle, content) = parseParagraphPrefix(line)
            let inlineRuns = parseInline(content, paragraphStyle: paragraphStyle)

            for run in inlineRuns {
                allText += run.text
                allRuns.append(run.run)
            }
            // Append trailing newline for every line
            allText += "\n"

            // The newline belongs to the last run of this line, so extend its length
            if let last = allRuns.last {
                let extended = DecodedRun(
                    length: last.length + 1,
                    paragraphStyle: last.paragraphStyle,
                    isBold: last.isBold,
                    isUnderlined: last.isUnderlined,
                    isStrikethrough: last.isStrikethrough,
                    link: last.link,
                    attachment: last.attachment
                )
                allRuns[allRuns.count - 1] = extended
            } else {
                // Empty line: create a plain run of length 1 for the newline
                allRuns.append(DecodedRun(
                    length: 1,
                    paragraphStyle: paragraphStyle,
                    isBold: false,
                    isUnderlined: false,
                    isStrikethrough: false,
                    link: nil,
                    attachment: nil
                ))
            }
        }

        let merged = mergeAdjacentRuns(allRuns)
        return DecodedNoteBody(text: allText, runs: merged)
    }

    // MARK: - Private helpers

    private struct Segment {
        let text: String
        let run: DecodedRun
    }

    /// Strips paragraph-level markers from a line and returns the style + remaining content.
    private static func parseParagraphPrefix(
        _ line: String
    ) -> (DecodedRun.DecodedParagraphStyle?, String) {
        // Checklist: "- [x] " or "- [ ] "
        if line.hasPrefix("- [x] ") {
            let content = String(line.dropFirst(6))
            let style = DecodedRun.DecodedParagraphStyle(
                styleType: nil, listStyle: nil,
                isChecklist: true, isChecklistDone: true,
                isBlockquote: false, indentAmount: 0
            )
            return (style, content)
        }
        if line.hasPrefix("- [ ] ") {
            let content = String(line.dropFirst(6))
            let style = DecodedRun.DecodedParagraphStyle(
                styleType: nil, listStyle: nil,
                isChecklist: true, isChecklistDone: false,
                isBlockquote: false, indentAmount: 0
            )
            return (style, content)
        }

        // Bullet list: "- "
        if line.hasPrefix("- ") {
            let content = String(line.dropFirst(2))
            let style = DecodedRun.DecodedParagraphStyle(
                styleType: nil, listStyle: 100,
                isChecklist: false, isChecklistDone: false,
                isBlockquote: false, indentAmount: 0
            )
            return (style, content)
        }

        // Numbered list: "N. " (one or more digits followed by ". ")
        if let range = line.range(of: #"^\d+\. "#, options: .regularExpression) {
            let content = String(line[range.upperBound...])
            let style = DecodedRun.DecodedParagraphStyle(
                styleType: nil, listStyle: 200,
                isChecklist: false, isChecklistDone: false,
                isBlockquote: false, indentAmount: 0
            )
            return (style, content)
        }

        // Blockquote: "> "
        if line.hasPrefix("> ") {
            let content = String(line.dropFirst(2))
            let style = DecodedRun.DecodedParagraphStyle(
                styleType: nil, listStyle: nil,
                isChecklist: false, isChecklistDone: false,
                isBlockquote: true, indentAmount: 0
            )
            return (style, content)
        }

        // Heading 3: "### "
        if line.hasPrefix("### ") {
            let content = String(line.dropFirst(4))
            let style = DecodedRun.DecodedParagraphStyle(
                styleType: .heading3, listStyle: nil,
                isChecklist: false, isChecklistDone: false,
                isBlockquote: false, indentAmount: 0
            )
            return (style, content)
        }

        // Heading 2: "## "
        if line.hasPrefix("## ") {
            let content = String(line.dropFirst(3))
            let style = DecodedRun.DecodedParagraphStyle(
                styleType: .heading2, listStyle: nil,
                isChecklist: false, isChecklistDone: false,
                isBlockquote: false, indentAmount: 0
            )
            return (style, content)
        }

        // Heading 1: "# "
        if line.hasPrefix("# ") {
            let content = String(line.dropFirst(2))
            let style = DecodedRun.DecodedParagraphStyle(
                styleType: .heading1, listStyle: nil,
                isChecklist: false, isChecklistDone: false,
                isBlockquote: false, indentAmount: 0
            )
            return (style, content)
        }

        return (nil, line)
    }

    /// Parses inline formatting tokens (**bold**, ~~strike~~, [text](url)) from a plain content string.
    private static func parseInline(
        _ content: String,
        paragraphStyle: DecodedRun.DecodedParagraphStyle?
    ) -> [Segment] {
        var segments: [Segment] = []
        var remaining = content

        while !remaining.isEmpty {
            // Try to find the earliest inline marker
            var earliestRange: Range<String.Index>? = nil
            var matchKind: InlineKind = .plain

            // Check for **bold**
            if let r = remaining.range(of: "**") {
                if earliestRange == nil || r.lowerBound < earliestRange!.lowerBound {
                    earliestRange = r
                    matchKind = .bold
                }
            }
            // Check for ~~strikethrough~~
            if let r = remaining.range(of: "~~") {
                if earliestRange == nil || r.lowerBound < earliestRange!.lowerBound {
                    earliestRange = r
                    matchKind = .strikethrough
                }
            }
            // Check for [link](url)
            if let r = remaining.range(of: "[", options: .literal) {
                if earliestRange == nil || r.lowerBound < earliestRange!.lowerBound {
                    earliestRange = r
                    matchKind = .link
                }
            }

            guard let startRange = earliestRange else {
                // No more markers — emit the rest as plain text
                segments.append(makeSegment(remaining, paragraphStyle: paragraphStyle,
                    isBold: false, isStrikethrough: false, link: nil))
                break
            }

            // Emit plain text before the marker
            let before = String(remaining[remaining.startIndex..<startRange.lowerBound])
            if !before.isEmpty {
                segments.append(makeSegment(before, paragraphStyle: paragraphStyle,
                    isBold: false, isStrikethrough: false, link: nil))
            }

            switch matchKind {
            case .bold:
                remaining = String(remaining[startRange.upperBound...])
                if let endRange = remaining.range(of: "**") {
                    let inner = String(remaining[remaining.startIndex..<endRange.lowerBound])
                    segments.append(makeSegment(inner, paragraphStyle: paragraphStyle,
                        isBold: true, isStrikethrough: false, link: nil))
                    remaining = String(remaining[endRange.upperBound...])
                } else {
                    // No closing marker — emit "**" + rest as plain
                    segments.append(makeSegment("**" + remaining, paragraphStyle: paragraphStyle,
                        isBold: false, isStrikethrough: false, link: nil))
                    remaining = ""
                }

            case .strikethrough:
                remaining = String(remaining[startRange.upperBound...])
                if let endRange = remaining.range(of: "~~") {
                    let inner = String(remaining[remaining.startIndex..<endRange.lowerBound])
                    segments.append(makeSegment(inner, paragraphStyle: paragraphStyle,
                        isBold: false, isStrikethrough: true, link: nil))
                    remaining = String(remaining[endRange.upperBound...])
                } else {
                    segments.append(makeSegment("~~" + remaining, paragraphStyle: paragraphStyle,
                        isBold: false, isStrikethrough: false, link: nil))
                    remaining = ""
                }

            case .link:
                // Parse [text](url)
                remaining = String(remaining[startRange.upperBound...])
                if let closeBracket = remaining.range(of: "]("),
                   let closeParen = remaining.range(of: ")", options: .literal,
                       range: closeBracket.upperBound..<remaining.endIndex) {
                    let linkText = String(remaining[remaining.startIndex..<closeBracket.lowerBound])
                    let url = String(remaining[closeBracket.upperBound..<closeParen.lowerBound])
                    segments.append(makeSegment(linkText, paragraphStyle: paragraphStyle,
                        isBold: false, isStrikethrough: false, link: url))
                    remaining = String(remaining[closeParen.upperBound...])
                } else {
                    // Not a valid link — emit "[" + rest as plain
                    segments.append(makeSegment("[" + remaining, paragraphStyle: paragraphStyle,
                        isBold: false, isStrikethrough: false, link: nil))
                    remaining = ""
                }

            case .plain:
                // Should not reach here
                break
            }
        }

        return segments
    }

    private enum InlineKind {
        case plain, bold, strikethrough, link
    }

    private static func makeSegment(
        _ text: String,
        paragraphStyle: DecodedRun.DecodedParagraphStyle?,
        isBold: Bool,
        isStrikethrough: Bool,
        link: String?
    ) -> Segment {
        let run = DecodedRun(
            length: text.count,
            paragraphStyle: paragraphStyle,
            isBold: isBold,
            isUnderlined: false,
            isStrikethrough: isStrikethrough,
            link: link,
            attachment: nil
        )
        return Segment(text: text, run: run)
    }

    /// Merges adjacent runs that have identical formatting.
    private static func mergeAdjacentRuns(_ runs: [DecodedRun]) -> [DecodedRun] {
        var result: [DecodedRun] = []
        for run in runs {
            if let last = result.last, runsAreEquivalent(last, run) {
                result[result.count - 1] = DecodedRun(
                    length: last.length + run.length,
                    paragraphStyle: last.paragraphStyle,
                    isBold: last.isBold,
                    isUnderlined: last.isUnderlined,
                    isStrikethrough: last.isStrikethrough,
                    link: last.link,
                    attachment: last.attachment
                )
            } else {
                result.append(run)
            }
        }
        return result
    }

    private static func runsAreEquivalent(_ a: DecodedRun, _ b: DecodedRun) -> Bool {
        guard a.isBold == b.isBold,
              a.isUnderlined == b.isUnderlined,
              a.isStrikethrough == b.isStrikethrough,
              a.link == b.link,
              a.attachment == nil && b.attachment == nil
        else { return false }

        return paragraphStylesEqual(a.paragraphStyle, b.paragraphStyle)
    }

    private static func paragraphStylesEqual(
        _ a: DecodedRun.DecodedParagraphStyle?,
        _ b: DecodedRun.DecodedParagraphStyle?
    ) -> Bool {
        switch (a, b) {
        case (nil, nil):
            return true
        case let (lhs?, rhs?):
            return lhs.styleType == rhs.styleType
                && lhs.listStyle == rhs.listStyle
                && lhs.isChecklist == rhs.isChecklist
                && lhs.isChecklistDone == rhs.isChecklistDone
                && lhs.isBlockquote == rhs.isBlockquote
                && lhs.indentAmount == rhs.indentAmount
        default:
            return false
        }
    }
}
