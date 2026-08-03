import CoreGraphics
import Foundation

/// Single source of truth for markdown type metrics, shared by the rendered
/// view (`MarkdownTextView`) and the live editor (`RichMarkdownEditor` /
/// `MarkdownUITextView`) so text does not change size or rhythm when a
/// reflection flips between reading and editing.
enum MarkdownTypeSpec: Sendable {
    // MARK: - Font families
    //
    // Only the faces bundled in grove/Resources/Fonts are referenced here.
    // IBM Plex Sans ships Light/Regular/Medium — Medium is the heaviest sans
    // face available, so it doubles as the emphasis (bold) face.

    enum FontName {
        static let body = "IBMPlexSans-Regular"
        static let bodyEmphasis = "IBMPlexSans-Medium"
        static let mono = "IBMPlexMono-Regular"
        static let monoEmphasis = "IBMPlexMono-SemiBold"
        static let heading = "Newsreader-Medium"
        static let headingEmphasis = "Newsreader-SemiBold"
        static let headingItalic = "Newsreader-MediumItalic"
        static let headingEmphasisItalic = "Newsreader-SemiBoldItalic"
    }

    // MARK: - Scales

    /// Reading/editing scale for a whole surface.
    enum Scale: Sendable {
        /// Reflection prose — matches `RichMarkdownEditor(proseMode: true)`.
        case prose
        /// Dense contexts (chat bubbles, inline previews).
        case compact

        var bodySize: CGFloat {
            switch self {
            case .prose: return MarkdownTypeSpec.proseBodySize
            case .compact: return 13
            }
        }

        var lineSpacing: CGFloat {
            switch self {
            case .prose: return MarkdownTypeSpec.proseLineSpacing
            case .compact: return 1
            }
        }

        var blockSpacing: CGFloat {
            switch self {
            case .prose: return MarkdownTypeSpec.proseParagraphSpacing
            case .compact: return 8
            }
        }

        var monoSize: CGFloat {
            MarkdownTypeSpec.monoSize(forBodySize: bodySize)
        }

        func headingSize(forLevel level: Int) -> CGFloat {
            MarkdownTypeSpec.headingSize(forLevel: level, bodySize: bodySize)
        }

        /// Leading indent applied per nesting level in bullet/ordered lists.
        var listNestIndent: CGFloat {
            switch self {
            case .prose: return 18
            case .compact: return 14
            }
        }
    }

    // MARK: - Prose metrics (mirrored by the NSTextView/UITextView editors)

    /// Point size used by the editors when `proseMode` is on.
    static let proseBodySize: CGFloat = 18
    static let proseLineSpacing: CGFloat = 2
    static let proseParagraphSpacing: CGFloat = 6

    static func monoSize(forBodySize bodySize: CGFloat) -> CGFloat {
        max(9, bodySize - 2)
    }

    /// Heading ramp shared with the editors' live highlighting.
    ///
    /// Deliberately shallower than a document ramp: reflections are notes
    /// living in a ~340pt rail, so an H1 should read as a note title, not
    /// shout like an article headline.
    static func headingSize(forLevel level: Int, bodySize: CGFloat) -> CGFloat {
        switch level {
        case 1: return (bodySize * 1.33).rounded()
        case 2: return (bodySize * 1.15).rounded()
        default: return (bodySize * 1.05).rounded()
        }
    }

    /// One level of nesting only — deeper indents collapse onto level 1.
    static func nestingLevel(forIndentation indentation: Int) -> Int {
        indentation >= 2 ? 1 : 0
    }
}
