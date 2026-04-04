import Foundation

enum NoteBodyEncoder: Sendable {
    static func encode(_ body: DecodedNoteBody) throws -> Data {
        var note = CNNote()
        note.noteText = body.text
        note.attributeRun = body.runs.map { run -> CNAttributeRun in
            var protoRun = CNAttributeRun()
            protoRun.length = Int32(run.length)
            if let ps = run.paragraphStyle {
                var style = CNParagraphStyle()
                if let st = ps.styleType { style.styleType = Int32(st.rawValue) }
                if let ls = ps.listStyle { style.listStyle = Int32(ls) }
                if ps.isChecklist {
                    var checklist = CNChecklist()
                    checklist.done = ps.isChecklistDone ? 1 : 0
                    style.checklist = checklist
                }
                if ps.isBlockquote { style.blockquote = 1 }
                if ps.indentAmount > 0 { style.indentAmount = Int32(ps.indentAmount) }
                protoRun.paragraphStyle = style
            }
            if run.isBold { protoRun.fontWeight = 1 }
            if run.isUnderlined { protoRun.underlined = 1 }
            if run.isStrikethrough { protoRun.strikethrough = 1 }
            if let link = run.link { protoRun.link = link }
            if let att = run.attachment {
                var info = CNAttachmentInfo()
                info.attachmentIdentifier = att.identifier
                info.typeUti = att.typeUTI
                protoRun.attachmentInfo = info
            }
            return protoRun
        }
        var doc = CNDocument()
        doc.note = note
        var proto = CNNoteStoreProto()
        proto.document = doc
        let rawData = try proto.serializedData()
        return try GzipHelper.compress(rawData)
    }
}
