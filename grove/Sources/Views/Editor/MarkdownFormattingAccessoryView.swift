#if os(iOS)
import UIKit

/// UIView-based inputAccessoryView providing a markdown formatting toolbar.
/// Displays above the keyboard with horizontal scrolling formatting buttons.
class MarkdownFormattingAccessoryView: UIView {
    weak var formattingDelegate: HighlightingUITextView?

    private let scrollView = UIScrollView()
    private let stackView = UIStackView()

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 44)
    }

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 44))
        autoresizingMask = .flexibleWidth
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        backgroundColor = .systemBackground

        // Top separator
        let separator = UIView()
        separator.backgroundColor = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)
        NSLayoutConstraint.activate([
            separator.topAnchor.constraint(equalTo: topAnchor),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
        ])

        // Scroll view
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: separator.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        // Stack view
        stackView.axis = .horizontal
        stackView.spacing = 2
        stackView.alignment = .center
        stackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 8),
            stackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -8),
            stackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            stackView.heightAnchor.constraint(equalTo: scrollView.heightAnchor),
        ])

        // Build buttons
        addButton(systemName: "bold", action: #selector(boldTapped))
        addButton(systemName: "italic", action: #selector(italicTapped))
        addSeparator()
        addButton(systemName: "number", action: #selector(headingTapped))
        addButton(systemName: "list.bullet", action: #selector(listTapped))
        addButton(systemName: "text.quote", action: #selector(quoteTapped))
        addSeparator()
        addButton(systemName: "chevron.left.forwardslash.chevron.right", action: #selector(codeTapped))
        addButton(systemName: "link", action: #selector(linkTapped))
        addButton(systemName: "link.badge.plus", action: #selector(wikiLinkTapped))
        addButton(systemName: "strikethrough", action: #selector(strikethroughTapped))
        addSeparator()
        addButton(systemName: "keyboard.chevron.compact.down", action: #selector(dismissKeyboard))
    }

    private func addButton(systemName: String, action: Selector) {
        let button = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        button.setImage(UIImage(systemName: systemName, withConfiguration: config), for: .normal)
        button.tintColor = .secondaryLabel
        button.addTarget(self, action: action, for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 44),
            button.heightAnchor.constraint(equalToConstant: 44),
        ])
        stackView.addArrangedSubview(button)
    }

    private func addSeparator() {
        let sep = UIView()
        sep.backgroundColor = .separator
        sep.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            sep.widthAnchor.constraint(equalToConstant: 1),
            sep.heightAnchor.constraint(equalToConstant: 20),
        ])
        stackView.addArrangedSubview(sep)
    }

    // MARK: - Actions

    @objc private func boldTapped() {
        formattingDelegate?.wrapSelectionWith(prefix: "**", suffix: "**")
    }

    @objc private func italicTapped() {
        formattingDelegate?.wrapSelectionWith(prefix: "*", suffix: "*")
    }

    @objc private func headingTapped() {
        formattingDelegate?.insertPrefixAtCurrentLine("## ")
    }

    @objc private func listTapped() {
        formattingDelegate?.insertPrefixAtCurrentLine("- ")
    }

    @objc private func quoteTapped() {
        formattingDelegate?.insertPrefixAtCurrentLine("> ")
    }

    @objc private func codeTapped() {
        formattingDelegate?.wrapSelectionWith(prefix: "`", suffix: "`")
    }

    @objc private func linkTapped() {
        formattingDelegate?.wrapSelectionWith(prefix: "[", suffix: "](url)")
    }

    @objc private func wikiLinkTapped() {
        formattingDelegate?.insertTextAtSelection("[[]]", cursorOffset: -2)
    }

    @objc private func strikethroughTapped() {
        formattingDelegate?.wrapSelectionWith(prefix: "~~", suffix: "~~")
    }

    @objc private func dismissKeyboard() {
        formattingDelegate?.resignFirstResponder()
    }
}
#endif
