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

    private static let moreTextPrefix = "… "
    private static let moreText = NSLocalizedString(
        "GROUP_DESCRIPTION_MORE",
        comment: "Text indication the user can tap to view the full group description"
    )
    private static let moreTextPlusPrefixLength = (moreTextPrefix + moreText).utf16.count

    private let textThatFitsCache = NSCache<NSString, NSString>(countLimit: 128)

    func truncateVisibleTextIfNecessary() {
        // When using autolayout, we need to initially set the text
        // to the full text otherwise the view will never get any width.
        if !shouldDeactivateConstraints {
            textView.text = descriptionText
        }

        guard width > 0 else { return }

        guard let descriptionText = descriptionText else { return }

        let cacheKey: NSString = "\(width)x\(height)-\(descriptionText)" as NSString

        // If we have already determine the attributed text for
        // this size + description, use it.
        if let cachedText = textThatFitsCache.object(forKey: cacheKey) {
            return setTextThatFits(cachedText as String)
        }

        var textThatFits = descriptionText
        defer {
            setTextThatFits(textThatFits)

            // Cache the text that fits for this size + description.
            textThatFitsCache.setObject(textThatFits as NSString, forKey: cacheKey)
        }

        setTextThatFits(textThatFits)
        var visibleCharacterRangeUpperBound = textView.visibleTextRange.upperBound

        // Check if we're displaying less than the full length of the description
        // text. If so, we will manually truncate and add a "more" button to view
        // the full description.
        guard visibleCharacterRangeUpperBound < textThatFits.utf16.count else { return }

        // We might fit without further truncation, for example if the description
        // contains new line characters, so set the possible new text immediately.
        textThatFits = (textThatFits as NSString).substring(
            to: visibleCharacterRangeUpperBound
        )

        setTextThatFits(textThatFits)
        visibleCharacterRangeUpperBound
            = textView.visibleTextRange.upperBound - Self.moreTextPlusPrefixLength

        // If we're still truncated, trim down the visible text until
        // we have space to fit the "more" link without truncation.
        // This should only take a few iterations.
        while visibleCharacterRangeUpperBound < textThatFits.utf16.count {
            let truncateToIndex = max(0, visibleCharacterRangeUpperBound)
            guard truncateToIndex > 0 else { break }

            textThatFits = (textThatFits as NSString).substring(to: truncateToIndex)

            setTextThatFits(textThatFits)
            visibleCharacterRangeUpperBound
                = textView.visibleTextRange.upperBound - Self.moreTextPlusPrefixLength
        }
    }

    func setTextThatFits(_ textThatFits: String) {
        if textThatFits == descriptionText {
            textView.dataDetectorTypes = .all
            textView.linkTextAttributes = [
                .foregroundColor: textColor ?? Theme.secondaryTextAndIconColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ]
            textView.text = textThatFits
        } else {
            textView.dataDetectorTypes = []
            textView.linkTextAttributes = [
                .foregroundColor: Theme.primaryTextColor,
                .underlineStyle: 0
            ]
            textView.attributedText = NSAttributedString.composed(of: [
                textThatFits.stripped,
                Self.moreTextPrefix,
                Self.moreText.styled(
                    with: .link(Self.viewFullDescriptionURL)
                )
            ]).styled(
                with: .font(font ?? .ows_dynamicTypeBody),
                .color(textColor ?? Theme.secondaryTextAndIconColor),
                .alignment(textAlignment)
            )
        }
    }
}

extension GroupDescriptionPreviewView: UITextViewDelegate {
    func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
        guard URL == Self.viewFullDescriptionURL else { return true }

        let vc = GroupDescriptionViewController(
            helper: GroupAttributesEditorHelper(
                groupId: Data(),
                groupNameOriginal: groupName,
                groupDescriptionOriginal: descriptionText,
                avatarOriginalData: nil,
                iconViewSize: 0
            )
        )
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
