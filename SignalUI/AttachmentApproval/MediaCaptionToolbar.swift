//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import SignalServiceKit
import UIKit

// Coincides with Android's max text message length
let kMaxMessageBodyCharacterCount = 2000

protocol MediaCaptionToolbarDelegate: AnyObject {
    func mediaCaptionToolbarWillBeginEditing(_ mediaCaptionToolbar: MediaCaptionToolbar)
    func mediaCaptionToolbarDidBeginEditing(_ mediaCaptionToolbar: MediaCaptionToolbar)
    func mediaCaptionToolbarDidEndEditing(_ mediaCaptionToolbar: MediaCaptionToolbar)
    func mediaCaptionToolbarDidChangeText(_ mediaCaptionToolbar: MediaCaptionToolbar)
    func mediaCaptionToolBarDidChangeHeight(_ mediaCaptionToolbar: MediaCaptionToolbar)
}

// MARK: -

class MediaCaptionToolbar: UIView, UITextViewDelegate, BodyRangesTextViewDelegate {

    // Forward text editing-related events to AttachmentApprovalToolbar.
    weak var delegate: MediaCaptionToolbarDelegate?

    // Forward mention-related calls directly to the view controller.
    weak var textViewDelegate: BodyRangesTextViewDelegate?

    private var isViewOnceEnabled: Bool = true

    private var isViewOnceOn: Bool = false

    func setIsViewOnce(enabled: Bool, on: Bool, animated: Bool) {
        guard isViewOnceEnabled != enabled || isViewOnceOn != on else { return }

        isViewOnceEnabled = enabled
        isViewOnceOn = on

        updateContent(animated: animated)
    }

    var isEditingText: Bool {
        textView.isFirstResponder
    }

    var messageBodyForSending: MessageBody? {
        // Ignore message text if "view-once" is on.
        guard isViewOnceOn == false else {
            return nil
        }
        return textView.messageBodyForSending
    }

    func setMessageBody(_ messageBody: MessageBody?, txProvider: EditableMessageBodyTextStorage.ReadTxProvider) {
        textView.setMessageBody(messageBody, txProvider: txProvider)
        updateAppearance(animated: false)
    }

    // MARK: - Initializers

    override init(frame: CGRect) {
        super.init(frame: frame)

        // Specifying autoresizing mask and an intrinsic content size allows proper
        // sizing when used as an input accessory view.
        autoresizingMask = .flexibleHeight
        directionalLayoutMargins = .init(hMargin: 0, vMargin: LayoutMetrics.verticalPadding)
        semanticContentAttribute = .forceLeftToRight

        // Either Done or Proceed button is visible at a time.
        // Embed both buttons in a fixed size wrapper view so that
        // stack view doesn't do re-layout when switching from one button to another.
        let buttonWrapper = UIView()
        buttonWrapper.addSubview(doneButton)
        buttonWrapper.addSubview(proceedButton)

        let contentStack = UIStackView(arrangedSubviews: [textViewContainer, buttonWrapper])
        contentStack.spacing = 12
        contentStack.alignment = .bottom // Align Done/Proceed buttons to the bottom when text is multi-line.
        addSubview(contentStack)

        doneButton.translatesAutoresizingMaskIntoConstraints = false
        proceedButton.translatesAutoresizingMaskIntoConstraints = false
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            doneButton.topAnchor.constraint(greaterThanOrEqualTo: buttonWrapper.topAnchor),
            doneButton.leadingAnchor.constraint(equalTo: buttonWrapper.leadingAnchor),
            doneButton.trailingAnchor.constraint(equalTo: buttonWrapper.trailingAnchor),
            doneButton.bottomAnchor.constraint(equalTo: buttonWrapper.bottomAnchor),

            proceedButton.topAnchor.constraint(greaterThanOrEqualTo: buttonWrapper.topAnchor),
            proceedButton.leadingAnchor.constraint(equalTo: buttonWrapper.leadingAnchor),
            proceedButton.trailingAnchor.constraint(equalTo: buttonWrapper.trailingAnchor),
            proceedButton.bottomAnchor.constraint(equalTo: buttonWrapper.bottomAnchor),

            buttonWrapper.widthAnchor.constraint(equalToConstant: LayoutMetrics.initialTextBoxHeight),
            buttonWrapper.heightAnchor.constraint(equalToConstant: LayoutMetrics.initialTextBoxHeight),

            contentStack.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            // This view (MediaCaptionToolbar) might dip into the bottom safe area,
            // increasing bottom layout margin. We want a stable 8 dp padding at all times
            // and therefore constrain to view's edge.
            contentStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -LayoutMetrics.verticalPadding),
        ])

        updateContent(animated: false)

        if #available(iOS 17, *) {
            registerForTraitChanges(
                [UITraitUserInterfaceStyle.self],
                handler: { (self: Self, _) in
                    // This will cause `BodyRangesTextView` to update attributes
                    // even though the color doesn't actually change.
                    self.textView.textColor = .Signal.label
                },
            )
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - UIView Overrides

    // Since we have `self.autoresizingMask = UIViewAutoresizingFlexibleHeight`, we must specify
    // an intrinsicContentSize. Specifying CGSize.zero causes the height to be determined by autolayout.
    override var intrinsicContentSize: CGSize { .zero }

    override var bounds: CGRect {
        didSet {
            guard oldValue.size.height != bounds.size.height else { return }

            // Compensate for autolayout frame/bounds changes when animating height change.
            // This logic ensures the input toolbar stays pinned to the keyboard visually.
            if isAnimatingHeightChange, textView.isFirstResponder {
                var frame = frame
                frame.origin.y = 0
                // In this conditional, bounds change is captured in an animation block, which we don't want here.
                UIView.performWithoutAnimation {
                    self.frame = frame
                }
            }
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        if #unavailable(iOS 17), traitCollection.userInterfaceStyle != previousTraitCollection?.userInterfaceStyle {
            textView.textColor = .Signal.label
        }
    }

    // MARK: - Layout

    private var isAnimatingHeightChange = false

    // Copied from StoryReplyInputToolbar
    private enum LayoutMetrics {
        static let initialTextBoxHeight: CGFloat = 40
        static let minTextViewHeight: CGFloat = 35
        static var maxTextViewHeight: CGFloat {
            // About ~4 lines in portrait and ~3 lines in landscape.
            // Otherwise we risk obscuring too much of the content.
            UIDevice.current.orientation.isPortrait ? 160 : 100
        }

        static let verticalPadding: CGFloat = 8
    }

    static var verticalPadding: CGFloat { LayoutMetrics.verticalPadding }

    // Active when editing text: support for multi-line text field.
    private var textViewHeightConstraint: NSLayoutConstraint!
    // Active when not editing text: restricts text field to a single line.
    private var textViewMinimumHeightConstraint: NSLayoutConstraint!

    private func updateContent(animated: Bool) {
        updateAppearance(animated: animated)
        updateHeight(animated: animated)
    }

    private func updateAppearance(animated: Bool) {
        viewOnceTextLabel.setIsHidden(!isViewOnceOn, animated: animated)
        viewOnceButton.isHidden = !isViewOnceEnabled
        viewOnceButton.configuration?.image = isViewOnceOn
            ? UIImage(imageLiteralResourceName: "view_once")
            : UIImage(imageLiteralResourceName: "viewonce-slash")

        if isViewOnceOn, isEditingText {
            _ = textView.resignFirstResponder()
        }

        let hasText = !textView.isEmpty
        textView.setIsHidden(isViewOnceOn, animated: animated)
        placeholderTextView.setIsHidden(hasText || isViewOnceOn, animated: animated)

        let isEditingText = isEditingText
        doneButton.setIsHidden(!isEditingText, animated: animated)
        proceedButton.setIsHidden(isEditingText, animated: animated)
    }

    private func updateHeight(animated: Bool) {
        guard let textViewHeightConstraint, let textViewMinimumHeightConstraint else {
            owsFailDebug("Missing constraints.")
            return
        }

        let isEditing = isEditingText

        let contentSize = textView.sizeThatFits(CGSize(width: textView.frame.width, height: .greatestFiniteMagnitude))
        let newHeight = CGFloat.clamp(
            contentSize.height.rounded(.up),
            min: LayoutMetrics.minTextViewHeight,
            max: LayoutMetrics.maxTextViewHeight,
        )
        // Update height if:
        // • text view height changes.
        // • we need to restrict/unrestrict text view to 1 line of text.
        guard
            (textViewHeightConstraint.constant != newHeight) ||
            (textViewHeightConstraint.isActive != isEditing)
        else {
            return
        }

        if animated {
            isAnimatingHeightChange = true
            let animator = UIViewPropertyAnimator(
                duration: 0.25, // ConversationInputToolbar.heightChangeAnimationDuration
                springDamping: 1,
                springResponse: 0.25,
            )
            animator.addAnimations {
                textViewHeightConstraint.constant = newHeight
                textViewHeightConstraint.isActive = isEditing
                textViewMinimumHeightConstraint.isActive = !isEditing

                self.delegate?.mediaCaptionToolBarDidChangeHeight(self)
            }
            animator.addCompletion { _ in
                self.isAnimatingHeightChange = false
            }
            animator.startAnimation()

        } else {
            textViewHeightConstraint.constant = newHeight
            textViewHeightConstraint.isActive = isEditing
            textViewMinimumHeightConstraint.isActive = !isEditing

            self.delegate?.mediaCaptionToolBarDidChangeHeight(self)
        }
    }

    // MARK: - Subviews

    private(set) lazy var textView: BodyRangesTextView = {
        let textView = buildTextView()
        textView.scrollIndicatorInsets = UIEdgeInsets(top: 5, left: 0, bottom: 5, right: 3)
        textView.bodyRangesDelegate = self
        return textView
    }()

    private lazy var placeholderTextView: UITextView = {
        let placeholderText = OWSLocalizedString(
            "MEDIA_EDITOR_CAPTION_PLACEHOLDER",
            comment: "Placeholder for message text input field in media editor.",
        )

        let placeholderTextView = buildTextView()
        placeholderTextView.setMessageBody(.init(text: placeholderText, ranges: .empty), txProvider: SSKEnvironment.shared.databaseStorageRef.readTxProvider)
        placeholderTextView.isEditable = false
        placeholderTextView.isUserInteractionEnabled = false
        placeholderTextView.textContainer.maximumNumberOfLines = 1
        placeholderTextView.textContainer.lineBreakMode = .byTruncatingTail
        placeholderTextView.textColor = .Signal.secondaryLabel
        return placeholderTextView
    }()

    private lazy var viewOnceTextLabel: UILabel = {
        let label = UILabel()
        label.text = OWSLocalizedString(
            "MEDIA_EDITOR_TEXT_FIELD_VIEW_ONCE_MEDIA",
            comment: "Shown in place of message input text in media editor when 'View Once' is on.",
        )
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.textAlignment = .center
        label.textColor = .Signal.secondaryLabel
        label.font = .dynamicTypeBodyClamped
        return label
    }()

    lazy var viewOnceButton: UIButton = {
        let button = UIButton(configuration: .plain())
        button.configuration?.contentInsets = .init(margin: 8) // makes 40 dp button - match `initialTextBoxHeight`
        button.configuration?.image = UIImage(imageLiteralResourceName: "viewonce-slash")
        return button
    }()

    // Wraps UITextView in a glass / semi-transparent pill-shaped view.
    private lazy var textViewContainer: UIView = {
        let textViewContainer = UIView()

        let backgroundView: UIView
        let contentView: UIView
        if #available(iOS 26, *) {
            let glassEffect = UIGlassEffect(style: .regular)
            glassEffect.tintColor = .Signal.glassBackgroundTint
            glassEffect.isInteractive = true
            let glassEffectView = UIVisualEffectView(effect: glassEffect)
            glassEffectView.cornerConfiguration = .uniformCorners(radius: .fixed(LayoutMetrics.initialTextBoxHeight / 2))
            glassEffectView.clipsToBounds = true
            glassEffectView.translatesAutoresizingMaskIntoConstraints = false
            textViewContainer.addSubview(glassEffectView)

            backgroundView = glassEffectView
            contentView = glassEffectView.contentView
        } else {
            backgroundView = UIView()
            backgroundView.backgroundColor = UIColor.Signal.tertiaryFill
            backgroundView.clipsToBounds = true
            backgroundView.layer.cornerRadius = LayoutMetrics.initialTextBoxHeight / 2
            backgroundView.translatesAutoresizingMaskIntoConstraints = false
            textViewContainer.addSubview(backgroundView)

            contentView = textViewContainer
        }

        // Wrap text views and "View Once" label into a wrapper view
        // that will be put into a horizontal stack view along with the "View Once" button.
        // This is done so that I can easily hide "View Once" button (eg when there are multiple media)
        // and let text views take entire horizontal space.
        let textViewWrapper = UIView()
        textViewWrapper.addSubview(placeholderTextView)
        textViewWrapper.addSubview(textView)
        textViewWrapper.addSubview(viewOnceTextLabel)
        textViewWrapper.translatesAutoresizingMaskIntoConstraints = false

        placeholderTextView.translatesAutoresizingMaskIntoConstraints = false
        textView.translatesAutoresizingMaskIntoConstraints = false
        viewOnceTextLabel.translatesAutoresizingMaskIntoConstraints = false

        // These two constraints will control height of the text view.
        textViewHeightConstraint = textView.heightAnchor.constraint(
            equalToConstant: LayoutMetrics.minTextViewHeight,
        )
        textViewMinimumHeightConstraint = textView.heightAnchor.constraint(
            equalToConstant: LayoutMetrics.minTextViewHeight,
        )

        NSLayoutConstraint.activate([
            // Only this constraint is activated because text view is made first responder later by user.
            textViewMinimumHeightConstraint,

            // Set minimum height on visible text input box.
            // Note that `textView` itself might be shorter - in that case it will be vertically centered within the wrapper.
            // It is done this way because `textView` should not be made taller than it's content size
            // as that causes incorrect vertical (top instead of center) alignment of text
            // when there's just a single line of it.
            textViewWrapper.heightAnchor.constraint(greaterThanOrEqualToConstant: LayoutMetrics.initialTextBoxHeight),

            textView.topAnchor.constraint(greaterThanOrEqualTo: textViewWrapper.topAnchor),
            textView.centerYAnchor.constraint(equalTo: textViewWrapper.centerYAnchor),
            textView.leadingAnchor.constraint(equalTo: textViewWrapper.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: textViewWrapper.trailingAnchor),

            placeholderTextView.topAnchor.constraint(equalTo: textView.topAnchor),
            placeholderTextView.leadingAnchor.constraint(equalTo: textView.leadingAnchor),
            placeholderTextView.trailingAnchor.constraint(equalTo: textView.trailingAnchor),
            placeholderTextView.bottomAnchor.constraint(equalTo: textView.bottomAnchor),

            viewOnceTextLabel.topAnchor.constraint(equalTo: textViewWrapper.topAnchor),
            viewOnceTextLabel.leadingAnchor.constraint(equalTo: textViewWrapper.leadingAnchor),
            viewOnceTextLabel.trailingAnchor.constraint(equalTo: textViewWrapper.trailingAnchor),
            viewOnceTextLabel.bottomAnchor.constraint(equalTo: textViewWrapper.bottomAnchor),
        ])

        // |[ Stretching text view] [View Once Button]|
        // If `viewOnceButton` is made hidden text views will occupy all the horizontal space automatically.
        viewOnceButton.setContentHuggingHorizontalHigh()
        let horizontalStack = UIStackView(arrangedSubviews: [textViewWrapper, viewOnceButton])
        // No spacing required as both text view and `viewOnceButton` have some padding embedded.
        horizontalStack.spacing = 0
        // Align Done/Proceed buttons to the bottom when text is multi-line.
        horizontalStack.alignment = .bottom
        horizontalStack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(horizontalStack)
        NSLayoutConstraint.activate([
            // Background view (glass pill or the simple pill-shaped view) is taking
            // entire resulting view, having the same frame as `horizontalStack`.
            backgroundView.topAnchor.constraint(equalTo: textViewContainer.topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: textViewContainer.leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: textViewContainer.trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: textViewContainer.bottomAnchor),

            // Horizontal stack is constrainer to all edges of the resulting view.
            // UIStackView will vertically center arranged subviews should their
            // height be less than the height of the stack view (eg text view grows in height
            // but View Once button stays the same).
            horizontalStack.topAnchor.constraint(equalTo: textViewContainer.topAnchor),
            horizontalStack.leadingAnchor.constraint(equalTo: textViewContainer.leadingAnchor),
            horizontalStack.trailingAnchor.constraint(equalTo: textViewContainer.trailingAnchor),
            horizontalStack.bottomAnchor.constraint(equalTo: textViewContainer.bottomAnchor),
        ])

        return textViewContainer
    }()

    lazy var doneButton: UIButton = {
        let button = UIButton(
            configuration: .tintedRoundMedia(image: Theme.iconImage(.checkmark)),
            primaryAction: UIAction { [weak self] _ in
                self?.didTapFinishEditing()
            },
        )
        button.accessibilityLabel = CommonStrings.doneButton
        return button
    }()

    lazy var proceedButton: UIButton = {
        let button = UIButton(configuration: .tintedRoundMedia(
            image: UIImage(imageLiteralResourceName: "arrow-up"), // will be updated later by AttachmentApprovalToolbar
        ))
        button.accessibilityLabel = CommonStrings.nextButton
        return button
    }()

    func setProceedButtonImage(_ buttonImage: UIImage) {
        proceedButton.configuration?.image = buttonImage
    }

    private func buildTextView() -> MediaCaptionTextView {
        let textView = MediaCaptionTextView()
        textView.backgroundColor = .clear
        textView.font = .dynamicTypeBodyClamped
        textView.keyboardAppearance = Theme.forceDarkThemeForMedia ? .dark : .default
        textView.tintColor = .Signal.label
        return textView
    }

    // MARK: - Actions

    func finishTextEditing() {
        textView.acceptAutocorrectSuggestion()
        _ = textView.resignFirstResponder()
    }

    private func didTapFinishEditing() {
        finishTextEditing()
    }

    // MARK: - BodyRangesTextViewDelegate

    func textViewDidBeginTypingMention(_ textView: BodyRangesTextView) {
        textViewDelegate?.textViewDidBeginTypingMention(textView)
    }

    func textViewDidEndTypingMention(_ textView: BodyRangesTextView) {
        textViewDelegate?.textViewDidEndTypingMention(textView)
    }

    func textViewMentionPickerParentView(_ textView: BodyRangesTextView) -> UIView? {
        return textViewDelegate?.textViewMentionPickerParentView(textView)
    }

    func textViewMentionPickerReferenceView(_ textView: BodyRangesTextView) -> UIView? {
        return textViewDelegate?.textViewMentionPickerReferenceView(textView)
    }

    func textViewMentionPickerPossibleAcis(_ textView: BodyRangesTextView, tx: DBReadTransaction) -> [Aci] {
        return textViewDelegate?.textViewMentionPickerPossibleAcis(textView, tx: tx) ?? []
    }

    func textViewDisplayConfiguration(_ textView: BodyRangesTextView) -> HydratedMessageBody.DisplayConfiguration {
        return .composingAttachment()
    }

    func mentionPickerStyle(_ textView: BodyRangesTextView) -> MentionPickerStyle {
        return .composingAttachment
    }

    func textViewMentionCacheInvalidationKey(_ textView: BodyRangesTextView) -> String {
        return textViewDelegate?.textViewMentionCacheInvalidationKey(textView) ?? UUID().uuidString
    }

    // MARK: - UITextViewDelegate

    func textViewDidChange(_ textView: UITextView) {
        updateContent(animated: true)
        delegate?.mediaCaptionToolbarDidChangeText(self)
    }

    func textViewShouldBeginEditing(_ textView: UITextView) -> Bool {
        delegate?.mediaCaptionToolbarWillBeginEditing(self)

        // Putting these lines in `textViewDidBeginEditing` doesn't work.
        textView.textContainer.lineBreakMode = .byWordWrapping
        textView.textContainer.maximumNumberOfLines = 0
        return true
    }

    func textViewDidBeginEditing(_ textView: UITextView) {
        // Making textView think its content has changed is necessary
        // in order to get correct textView size and expand it to multiple lines if necessary.
        textView.layoutManager.processEditing(
            for: textView.textStorage,
            edited: .editedCharacters,
            range: NSRange(location: 0, length: 0),
            changeInLength: 0,
            invalidatedRange: NSRange(location: 0, length: 0),
        )
        delegate?.mediaCaptionToolbarDidBeginEditing(self)
        updateContent(animated: true)
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        // We want to collapse the no-longer-editing text view to one line. If
        // it has multiple lines, and we're focused anywhere other than the
        // first line, this will make the text view appear blank; instead, put
        // the cursor at the front.
        let startTextPosition = textView.beginningOfDocument
        textView.textContainer.lineBreakMode = .byTruncatingTail
        textView.textContainer.maximumNumberOfLines = 1
        textView.selectedTextRange = textView.textRange(from: startTextPosition, to: startTextPosition)

        delegate?.mediaCaptionToolbarDidEndEditing(self)
        updateContent(animated: true)
    }
}

private class MediaCaptionTextView: BodyRangesTextView {

    private var textIsChanging = false

    override func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        textIsChanging = true
        return super.textView(self, shouldChangeTextIn: range, replacementText: text)
    }

    override func textViewDidChange(_ textView: UITextView) {
        super.textViewDidChange(textView)
        textIsChanging = false
    }

    override func isEditableMessageBodyDarkThemeEnabled() -> Bool {
        Theme.forceDarkThemeForMedia || Theme.isDarkThemeEnabled
    }
}
