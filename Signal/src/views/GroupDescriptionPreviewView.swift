//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import BonMot

class GroupDescriptionPreviewView: ManualLayoutView {
    private let textView = LinkingTextView()
    var descriptionText: String? { didSet { truncateVisibleTextIfNecessary() } }
    var groupName: String?
    private static let viewFullDescriptionURL = URL(string: "view-full-description")!

    var font: UIFont? {
        get { textView.font }
        set { textView.font = newValue }
    }

    var textColor: UIColor? {
        get { textView.textColor }
        set { textView.textColor = newValue }
    }

    var numberOfLines: Int {
        get { textView.textContainer.maximumNumberOfLines }
        set { textView.textContainer.maximumNumberOfLines = newValue }
    }

    var textAlignment: NSTextAlignment {
        get { textView.textAlignment }
        set { textView.textAlignment = newValue }
    }

    func apply(config: CVLabelConfig) {
        font = config.font
        textColor = config.textColor
        numberOfLines = config.numberOfLines
        textAlignment = config.textAlignment ?? .natural
        descriptionText = config.stringValue
    }

    init(shouldDeactivateConstraints: Bool = false) {
        super.init(name: "GroupDescriptionPreview")
        self.shouldDeactivateConstraints = shouldDeactivateConstraints

        textView.delegate = self

        addSubview(textView) { [weak self] view in
            if shouldDeactivateConstraints {
                self?.textView.frame = view.bounds
            }
            self?.truncateVisibleTextIfNecessary()
        }
        textView.autoPinEdgesToSuperviewEdges()
    }

    @objc required init(name: String) {
        fatalError("init(name:) has not been implemented")
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        textView.sizeThatFits(size)
    }

    private static let truncatedTextCache = NSCache<NSString, NSAttributedString>()
    func truncateVisibleTextIfNecessary() {
        textView.linkTextAttributes = [
            .foregroundColor: Theme.primaryTextColor,
            .underlineStyle: 0
        ]

        textView.text = descriptionText

        guard width > 0 else { return }

        guard let descriptionText = descriptionText else { return }

        let cacheKey: NSString = "\(width)x\(height)-\(descriptionText)" as NSString

        // If we have already determine the attributed text for
        // this size + description, use it.
        if let attributedText = Self.truncatedTextCache.object(forKey: cacheKey) {
            textView.attributedText = attributedText
            return
        }

        defer {
            // Cache the attributed text for this size + description.
            Self.truncatedTextCache.setObject(
                textView.attributedText,
                forKey: cacheKey
            )
        }

        var visibleCharacterRange = textView.visibleTextRange

        // Check if we're displaying less than the full length of the description
        // text. If so, we will manually truncate and add a "more" button to view
        // the full description.
        guard visibleCharacterRange.upperBound < textView.text.utf16.count else { return }

        let moreTextPrefix = "… "
        let moreText = NSLocalizedString(
            "GROUP_DESCRIPTION_MORE",
            comment: "Text indication the user can tap to view the full group description"
        )
        let moreTextPlusPrefix = moreTextPrefix + moreText

        // We might fit without further truncation, for example if the description
        // contains new line characters, so set the possible new text immediately.
        var truncatedText = (descriptionText as NSString).substring(
            to: visibleCharacterRange.upperBound
        )
        textView.text = truncatedText + moreTextPlusPrefix
        visibleCharacterRange = textView.visibleTextRange

        // If we're still truncated, trim down the visible text until
        // we have space to fit the "more" link without truncation.
        // This should only take a few iterations.
        while visibleCharacterRange.upperBound < textView.text.utf16.count {
            textView.text = truncatedText + moreTextPlusPrefix
            let truncateToIndex = max(0, visibleCharacterRange.upperBound - moreTextPlusPrefix.utf16.count)
            guard truncateToIndex > 0 else { break }
            truncatedText = (truncatedText as NSString).substring(to: truncateToIndex)

            visibleCharacterRange = textView.visibleTextRange
        }

        textView.attributedText = NSAttributedString.composed(of: [
            truncatedText.stripped,
            moreTextPrefix,
            moreText.styled(
                with: .link(Self.viewFullDescriptionURL)
            )
        ]).styled(
            with: .font(font ?? .ows_dynamicTypeBody),
            .color(textColor ?? Theme.secondaryTextAndIconColor),
            .alignment(textAlignment)
        )
    }
}

extension GroupDescriptionPreviewView: UITextViewDelegate {
    func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
        guard URL == Self.viewFullDescriptionURL else { return true }

        // Build a fake group model just to present the text.
        // This allows us to keep `GroupDescriptionViewController`
        // simple and reusable in many contexts.
        var builder = TSGroupModelBuilder()
        builder.name = groupName
        builder.descriptionText = descriptionText
        guard let groupModel = databaseStorage.read(
            block: { try? builder.buildAsV2(transaction: $0) }
        ) else {
            owsFailDebug("Failed to prepare group model")
            return false
        }

        let vc = GroupDescriptionViewController(groupModel: groupModel)
        UIApplication.shared.frontmostViewController?.presentFormSheet(
            OWSNavigationController(rootViewController: vc),
            animated: true
        )

        return false
    }
}

private extension UITextView {
    var visibleTextRange: NSRange {
        guard let start = closestPosition(to: contentOffset),
              let end = characterRange(
                at: CGPoint(
                    x: contentOffset.x + bounds.maxX,
                    y: contentOffset.y + bounds.maxY
                )
              )?.end else { return NSRange(location: 0, length: 0) }
        return NSRange(
            location: offset(from: beginningOfDocument, to: start),
            length: offset(from: start, to: end)
        )
    }
}
