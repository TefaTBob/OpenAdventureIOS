import Foundation

/// Turns the game transcript into screen rows of a fixed width.
///
/// The game's messages are hard-wrapped near 70 columns for an 80-column
/// terminal. On a 40-column screen we re-join prose lines into paragraphs
/// before wrapping, so text flows naturally instead of leaving ragged
/// half-lines. Short lines (inventory lists, prompts) are never joined.
enum TextLayout {
    /// Rows for the completed part of the transcript (everything but the
    /// line still in progress).
    static func rows(forCompleted lines: ArraySlice<String>, columns: Int, uppercase: Bool) -> [String] {
        let source = columns < 80 ? paragraphs(lines) : Array(lines)
        var rows: [String] = []
        rows.reserveCapacity(source.count + source.count / 2)
        for line in source {
            rows.append(contentsOf: wrap(uppercase ? line.uppercased() : line, width: columns))
        }
        return rows
    }

    /// Rows for the live line (prompt + typed input), plus the cursor column
    /// on its last row.
    static func liveRows(_ text: String, columns: Int, uppercase: Bool) -> (rows: [String], cursorColumn: Int) {
        let line = uppercase ? text.uppercased() : text
        // Hard-wrap so the cursor position is predictable while typing.
        var rows: [String] = []
        var rest = Substring(line)
        while rest.count > columns {
            rows.append(String(rest.prefix(columns)))
            rest = rest.dropFirst(columns)
        }
        rows.append(String(rest))
        var cursor = rows[rows.count - 1].count
        if cursor >= columns {
            rows.append("")
            cursor = 0
        }
        return (rows, cursor)
    }

    static func paragraphs(_ lines: ArraySlice<String>) -> [String] {
        var out: [String] = []
        var joinNext = false
        for line in lines {
            let isPrompt = line.hasPrefix(">")
            if joinNext, !line.isEmpty, !isPrompt, let last = out.popLast() {
                out.append(last + " " + line.drop(while: { $0 == " " }))
            } else {
                out.append(line)
            }
            // The game wraps prose near 70 columns; a long line means the
            // sentence probably continues on the next one.
            joinNext = line.count >= 50 && !isPrompt
        }
        return out
    }

    /// Greedy word wrap; words longer than the width are broken.
    static func wrap(_ text: String, width: Int) -> [String] {
        guard text.count > width else { return [text] }
        var rows: [String] = []
        var rest = Substring(text)
        while rest.count > width {
            let window = rest.prefix(width + 1)
            if let space = window.lastIndex(of: " "), space > rest.startIndex {
                rows.append(String(rest[..<space]))
                rest = rest[rest.index(after: space)...]
            } else {
                rows.append(String(rest.prefix(width)))
                rest = rest.dropFirst(width)
            }
        }
        rows.append(String(rest))
        return rows
    }
}
