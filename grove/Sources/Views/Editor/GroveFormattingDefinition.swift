#if os(macOS)
import SwiftUI

// MARK: - Grove Formatting Definition

/// Defines how Grove's semantic markdown attributes map to visual presentation
/// in the new SwiftUI TextEditor(text:selection:) API.
@available(macOS 26, *)
struct GroveFormattingDefinition {
    let fontSize: CGFloat

    init(fontSize: CGFloat = 15) {
        self.fontSize = fontSize
    }

    // MARK: - Fonts

    var bodyFont: Font {
        .custom("IBMPlexSans-Regular", size: fontSize)
    }

    var boldFont: Font {
        .custom("IBMPlexSans-Medium", size: fontSize)
    }

    var italicFont: Font {
        .custom("IBMPlexSans-Regular", size: fontSize).italic()
    }

    var monoFont: Font {
        .custom("IBMPlexMono-Regular", size: fontSize - 2)
    }

    var headingH1Font: Font {
        .custom("Newsreader-Medium", size: round(fontSize * 1.55))
    }

    var headingH2Font: Font {
        .custom("Newsreader-Medium", size: round(fontSize * 1.22))
    }

    /// Apply visual attributes to an AttributedString based on Grove semantic attributes.
    func applyPresentation(to attributedString: inout AttributedString) {
        for run in attributedString.runs {
            let range = run.range

            // Heading
            if let level = run.headingLevel {
                attributedString[range].font = level <= 1 ? headingH1Font : headingH2Font
                attributedString[range].foregroundColor = Color.textPrimary
            }

            // Bold + Italic
            if run.bold == true && run.italic == true {
                attributedString[range].font = boldFont.italic()
            } else if run.bold == true {
                attributedString[range].font = boldFont
            } else if run.italic == true {
                attributedString[range].font = italicFont
            }

            // Inline code
            if run.inlineCode == true {
                attributedString[range].font = monoFont
                attributedString[range].backgroundColor = Color.textTertiary.opacity(0.15)
            }

            // Strikethrough
            if run.strikethrough == true {
                attributedString[range].strikethroughStyle = .single
            }

            // Wiki link
            if run.wikiLink != nil {
                attributedString[range].underlineStyle = .single
                attributedString[range].foregroundColor = Color.textSecondary
            }

            // Link
            if run.mdLink != nil {
                attributedString[range].underlineStyle = .single
                attributedString[range].foregroundColor = Color.textSecondary
            }

            // Block quote
            if run.blockQuote == true {
                attributedString[range].foregroundColor = Color.textSecondary
            }

            // Code block
            if run.codeBlock != nil {
                attributedString[range].font = monoFont
                attributedString[range].backgroundColor = Color.textTertiary.opacity(0.1)
            }

            // List item — rendered as regular text, the "- " prefix is handled during serialization
        }
    }
}
#endif
