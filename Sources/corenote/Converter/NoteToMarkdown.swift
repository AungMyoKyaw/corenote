// MARK: - NoteToMarkdown

enum NoteToMarkdown: Sendable {

    /// Converts a `DecodedNoteBody` into a Markdown string.
    static func convert(_ body: DecodedNoteBody) -> String {
        var result = ""
        var textIndex = body.text.startIndex

        for run in body.runs {
            // Compute the end index for this run's character slice
            let runEnd = body.text.index(
                textIndex,
                offsetBy: run.length,
                limitedBy: body.text.endIndex
            ) ?? body.text.endIndex

            let runText = String(body.text[textIndex..<runEnd])
            textIndex = runEnd

            // Handle attachment run: the text is the object replacement character U+FFFC
            if let attachment = run.attachment {
                let placeholder = attachmentPlaceholder(attachment)
                result += placeholder
                continue
            }

            // Split the run text into lines, preserving whether a trailing newline exists
            let lines = runText.components(separatedBy: "\n")

            for (lineIndex, line) in lines.enumerated() {
                let isLastPart = lineIndex == lines.count - 1

                // Skip empty trailing segment after final newline
                if isLastPart && line.isEmpty {
                    break
                }

                // Apply inline formatting to the line content
                var formatted = applyInlineFormatting(line, run: run)

                // Apply paragraph-level prefix
                if let style = run.paragraphStyle {
                    formatted = applyParagraphPrefix(formatted, style: style)
                }

                result += formatted

                // Re-add the newline between lines (not after the last segment)
                if !isLastPart {
                    result += "\n"
                }
            }
        }

        // Trim trailing whitespace/newlines
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Private helpers

    private static func applyInlineFormatting(_ text: String, run: DecodedRun) -> String {
        var s = text

        // Skip empty content
        guard !s.isEmpty else { return s }

        // Remove the attachment placeholder character from inline text if it appears
        // (attachment runs are handled separately, but guard here just in case)
        let objectReplacement: Character = "\u{FFFC}"
        s = s.filter { $0 != objectReplacement }
        guard !s.isEmpty else { return "" }

        // Apply link first (wraps other formatting)
        if let url = run.link {
            s = "[\(s)](\(url))"
            return s
        }

        // Bold: **text**
        if run.isBold {
            s = "**\(s)**"
        }

        // Strikethrough: ~~text~~
        if run.isStrikethrough {
            s = "~~\(s)~~"
        }

        return s
    }

    private static func applyParagraphPrefix(
        _ text: String,
        style: DecodedRun.DecodedParagraphStyle
    ) -> String {
        // Indentation
        let indent = String(repeating: "  ", count: style.indentAmount)

        // Checklist
        if style.isChecklist {
            let check = style.isChecklistDone ? "- [x] " : "- [ ] "
            return indent + check + text
        }

        // Bullet or numbered list
        if let listStyle = style.listStyle {
            if listStyle == 200 {
                // Numbered list — use a generic marker; actual numbering would need context
                return indent + "1. " + text
            } else {
                // Bullet (100 or any other value)
                return indent + "- " + text
            }
        }

        // Blockquote
        if style.isBlockquote {
            return indent + "> " + text
        }

        // Heading styles
        if let styleType = style.styleType {
            switch styleType {
            case .title:
                return "# " + text
            case .heading1:
                return "# " + text
            case .heading2:
                return "## " + text
            case .heading3:
                return "### " + text
            }
        }

        return indent + text
    }

    private static func attachmentPlaceholder(
        _ attachment: DecodedRun.DecodedAttachment
    ) -> String {
        let uti = attachment.typeUTI.lowercased()
        let label: String
        if uti.contains("jpeg") || uti.contains("jpg") || uti.contains("png")
            || uti.contains("gif") || uti.contains("image")
        {
            label = "Image"
        } else if uti.contains("video") || uti.contains("movie") {
            label = "Video"
        } else if uti.contains("audio") || uti.contains("sound") {
            label = "Audio"
        } else {
            label = "Attachment"
        }
        return "[\(label): \(attachment.identifier)]"
    }
}
