//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import BonMot
import SignalUI

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

    @objc
    required init(name: String) {
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

    private let textThatFitsCache = LRUCache<String, String>(maxSize: 128)

    func truncateVisibleTextIfNecessary() {
        // When using autolayout, we need to initially set the text
        // to the full text otherwise the view will never get any width.
        if !shouldDeactivateConstraints {
            textView.text = descriptionText
        }

        guard width > 0 else { return }

        guard let descriptionText = descriptionText else { return }

        let cacheKey = "\(width)x\(height)-\(descriptionText)"

        // If we have already determine the attributed text for
        // this size + description, use it.
        if let cachedText = textThatFitsCache.object(forKey: cacheKey) {
            return setTextThatFits(cachedText)
        }

        var textThatFits = descriptionText
        defer {
            setTextThatFits(textThatFits)

            // Cache the text that fits for this size + description.
            textThatFitsCache.setObject(textThatFits, forKey: cacheKey)
        }

        setTextThatFits(textThatFits)
        var visibleCharacterRangeUpperBound = textView.visibleTextRange.upperBound

        // Check if we're displaying less than the full length of the description
        // text. If so, we will manually truncate and add a "more" button to view
        // the full description.
        guard visibleCharacterRangeUpperBound < textThatFits.utf16.count else { return }

        // We might fit without further truncation, for example if the description
        // contains new line characters, so set the possible new text immediately.
        textThatFits = textThatFits.substring(to: visibleCharacterRangeUpperBound)

        setTextThatFits(textThatFits)
        visibleCharacterRangeUpperBound
            = textView.visibleTextRange.upperBound - Self.moreTextPlusPrefixLength

        // If we're still truncated, trim down the visible text until
        // we have space to fit the "more" link without truncation.
        // This should only take a few iterations.
        var iterationCount = 0
        while visibleCharacterRangeUpperBound < textThatFits.utf16.count {
            let truncateToIndex = max(0, visibleCharacterRangeUpperBound)
            guard truncateToIndex > 0 else { break }

            textThatFits = textThatFits.substring(to: truncateToIndex)

            setTextThatFits(textThatFits)
            visibleCharacterRangeUpperBound
                = textView.visibleTextRange.upperBound - Self.moreTextPlusPrefixLength

            iterationCount += 1
            if iterationCount >= 10 {
                owsFailDebug("Failed to calculate visible range for description text. Bailing.")
                break
            }
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
        if #available(iOS 16, *) {
            engageTextKit1Fallback()
        }

        guard
            let start = closestPosition(to: contentOffset),
            let end = characterRange(
                at: CGPoint(
                    x: contentOffset.x + bounds.maxX,
                    y: contentOffset.y + bounds.maxY
                )
            )?.end
        else {
            return NSRange(location: 0, length: 0)
        }

        return NSRange(
            location: offset(from: beginningOfDocument, to: start),
            length: offset(from: start, to: end)
        )
    }

    /// Force this ``UITextView`` to fall back to TextKit 1 instead of using
    /// TextKit 2.
    ///
    /// With iOS 16, ``UITextView`` by default uses TextKit 2 to manage text
    /// layout under the hood, while older iOS versions use TextKit 1. However,
    /// accessing the `layoutManager` property on a ``UITextView`` will
    /// cause it to dynamically fall back to TextKit 1 for layout.
    ///
    /// TextKit 2 appears to come with some behavior differences (possibly
    /// bugs). Use this method to work around any issues by forcing TextKit 1.
    ///
    /// Notably, calling `closestPosition(to:)` and `characterRange(at:)` in
    /// the method above produced different (and potentially buggy) values on
    /// iOS 16 than on iOS 15. Specifically, on iOS 16 both methods seem to
    /// always return the end of the text, regardless of the points passed,
    /// which produced a bug in which long group descriptions were not being
    /// correctly detected and the "Read More" suffix was not being inserted.
    /// If you are reading this with the goal of doing away with this workaround
    /// (and potentially moving to using TextKit 2), please ensure that long
    /// group descriptions are correctly detected and handled on all iOS
    /// versions 16+!
    ///
    /// Some sources:
    ///
    /// - https://developer.apple.com/forums/thread/707410
    /// - From the doc comment on ``UITextView#layoutManager``:
    ///     > "To ensure compatibility with older code, accessing the
    ///     > .layoutManager of a UITextView - or its .textContainer's
    ///     > .layoutManager - will cause a UITextView that's using TextKit 2 to
    ///     > 'fall back' to TextKit 1, and return a newly created
    ///     > NSLayoutManager. After this happens, .textLayoutManager will return
    ///     > nil - and _any TextKit 2 objects you may have cached will cease
    ///     > functioning_. Be careful about this if you are intending to be using
    ///     > TextKit 2!"
    /// - From the doc comment on ``UITextView.textView(usingTextLayoutManager:)``:
    ///     > "From iOS 16 onwards, UITextViews are, by default, created with a
    ///     > TextKit 2 NSTextLayoutManager managing text layout (see the
    ///     > .textLayoutManager property). They will dynamically 'fall back' to
    ///     > a TextKit 1 NSLayoutManager if TextKit 1 features are used
    ///     > (notably, if the .layoutManager property is accessed). This
    ///     > convenience initializer can be used to specify TextKit 1 by
    ///     > default if you know code in your app relies on that. This avoids
    ///     > inefficiencies associated with the needless creation of a
    ///     > NSTextLayoutManager and the subsequent fallback."
    @available(iOS 16, *)
    private func engageTextKit1Fallback() {
        _ = layoutManager
    }
}
