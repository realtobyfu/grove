import Foundation

enum MarkdownLineParser {
    static func blockquoteContent(in line: String) -> String? {
        var cursor = line[...]

        while let first = cursor.first, first == " " || first == "\t" {
            cursor = cursor.dropFirst()
        }

        guard cursor.first == ">" else { return nil }
        cursor = cursor.dropFirst()

        while let first = cursor.first, first == " " || first == "\t" {
            cursor = cursor.dropFirst()
        }

        return String(cursor)
    }

    static func isBlockquoteLine(_ line: String) -> Bool {
        blockquoteContent(in: line) != nil
    }
}
