import Foundation

enum MarkdownEditorMode: String, CaseIterable, Sendable {
    case livePreview = "livePreview"
    case source = "source"

    var title: String {
        switch self {
        case .livePreview:
            return "Live Preview"
        case .source:
            return "Source"
        }
    }
}
