//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import UIKit

// Coincides with Android's max text message length
let kMaxMessageBodyCharacterCount = 2000

protocol AttachmentTextToolbarDelegate: class, MentionTextViewDelegate {
    func attachmentTextToolbarDidTapSend(_ attachmentTextToolbar: AttachmentTextToolbar)
    func attachmentTextToolbarDidBeginEditing(_ attachmentTextToolbar: AttachmentTextToolbar)
    func attachmentTextToolbarDidEndEditing(_ attachmentTextToolbar: AttachmentTextToolbar)
    func attachmentTextToolbarDidChange(_ attachmentTextToolbar: AttachmentTextToolbar)
    func attachmentTextToolbarDidViewOnce(_ attachmentTextToolbar: AttachmentTextToolbar)

    var isViewOnceEnabled: Bool { get set }
}

// MARK: -

class AttachmentTextToolbar: UIView, MentionTextViewDelegate {

    var options: AttachmentApprovalViewControllerOptions {
        didSet {
            updateContent()
        }
    }

    weak var attachmentTextToolbarDelegate: AttachmentTextToolbarDelegate?

    var isViewOnceEnabled: Bool {
        return options.contains(.canToggleViewOnce) && attachmentTextToolbarDelegate?.isViewOnceEnabled ?? false
    }

    var messageBody: MessageBody? {
        get {
            // Ignore message text if "view-once" is enabled.
            guard !isViewOnceEnabled else {
                return nil
            }
            return textView.messageBody
        }

        set {
            textView.messageBody = newValue
            updatePlaceholderTextViewVisibility()
        }
    }

    var recipientNames = [String]() {
        didSet { updateRecipientNames() }
    }

    private let viewOnceWrapper = UIView()

    // Layout Constants

    let kMinToolbarItemHeight: CGFloat = 40
    let kMinTextViewHeight: CGFloat = 36
    var maxTextViewHeight: CGFloat {
        // About ~4 lines in portrait and ~3 lines in landscape.
        // Otherwise we risk obscuring too much of the content.
        return UIDevice.current.orientation.isPortrait ? 160 : 100
    }
    var textViewHeightConstraint: NSLayoutConstraint?
    let kToolbarMargin: CGFloat = 8

    // MARK: - Initializers

    init(options: AttachmentApprovalViewControllerOptions, sendButtonImageName: String) {
        self.options = options

        super.init(frame: CGRect.zero)

        // Specifying autorsizing mask and an intrinsic content size allows proper
        // sizing when used as an input accessory view.
        self.autoresizingMask = .flexibleHeight
        self.translatesAutoresizingMaskIntoConstraints = false
        self.backgroundColor = UIColor.clear

        textView.mentionDelegate = self

        let sendButton = OWSButton.sendButton(imageName: sendButtonImageName) { [weak self] in
            guard let self = self else { return }
            self.didTapSend()
        }
        sendButton.accessibilityLabel = NSLocalizedString("ATTACHMENT_APPROVAL_SEND_BUTTON", comment: "Label for 'send' button in the 'attachment approval' dialog.")

        viewOnceButton.block = { [weak self] in
            self?.didTapViewOnceMessagesButton()
        }
        // Vertically center and increase hit area of button, except on right side for symmetrical layout WRT the input text field
        viewOnceButton.contentEdgeInsets =
            UIEdgeInsets(top: 6,
                         left: 8,
                         bottom: (kMinToolbarItemHeight - timerHeight) / 2,
                         right: 0)

        // Layout

        let sendWrapper = UIView()
        sendWrapper.addSubview(sendButton)
        viewOnceWrapper.addSubview(viewOnceButton)

        let hStackView = UIStackView()
        hStackView.isLayoutMarginsRelativeArrangement = true
        hStackView.layoutMargins = UIEdgeInsets(top: kToolbarMargin, left: kToolbarMargin, bottom: kToolbarMargin, right: kToolbarMargin)
        hStackView.axis = .horizontal
        hStackView.alignment = .bottom
        hStackView.spacing = kToolbarMargin

        var views = [ viewOnceWrapper, viewOnceSpacer, viewOnceRecipientNamesLabelScrollView, textContainer, sendWrapper ]
        // UIStackView's horizontal layout is leading-to-trailing.
        // We want left-to-right ordering, so reverse if RTL.
        if CurrentAppContext().isRTL {
            views.reverse()
        }
        for view in views {
            hStackView.addArrangedSubview(view)
        }

        let vStackView = UIStackView(arrangedSubviews: [recipientNamesLabelScrollView, hStackView])
        vStackView.axis = .vertical
        vStackView.spacing = 12
        self.addSubview(vStackView)
        vStackView.autoPinEdgesToSuperviewEdges()

        textViewHeightConstraint = textView.autoSetDimension(.height, toSize: kMinTextViewHeight)
        viewOnceRecipientNamesLabelScrollView.autoSetDimension(.height, toSize: kMinTextViewHeight, relation: .greaterThanOrEqual)
        viewOnceSpacer.autoSetDimension(.height, toSize: kMinTextViewHeight, relation: .greaterThanOrEqual)

        // We pin edges explicitly rather than doing something like:
        //  textView.autoPinEdges(toSuperviewMarginsExcludingEdge: .right)
        // because that method uses `leading` / `trailing` rather than `left` vs. `right`.
        // So it doesn't work as expected with RTL layouts when we explicitly want something
        // to be on the right side for both RTL and LTR layouts, like with the send button.
        // I believe this is a bug in PureLayout. Filed here: https://github.com/PureLayout/PureLayout/issues/209
        textContainer.autoPinEdge(toSuperviewMargin: .top)
        textContainer.autoPinEdge(toSuperviewMargin: .bottom)

        let layoutButtonWithinWrapper = { (button: UIView) in
            button.autoPinEdgesToSuperviewEdges(with: .zero, excludingEdge: .top)
            button.autoPinEdge(toSuperviewEdge: .top, withInset: 0, relation: .greaterThanOrEqual)
            NSLayoutConstraint.autoSetPriority(.defaultLow) {
                button.autoPinEdge(toSuperviewEdge: .top)
            }

            button.setContentHuggingHigh()
            button.setCompressionResistanceHigh()
        }
        layoutButtonWithinWrapper(sendButton)
        layoutButtonWithinWrapper(viewOnceButton)

        updateContent()
    }

    required init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    // MARK: - UIView Overrides

    override var intrinsicContentSize: CGSize {
        get {
            // Since we have `self.autoresizingMask = UIViewAutoresizingFlexibleHeight`, we must specify
            // an intrinsicContentSize. Specifying CGSize.zero causes the height to be determined by autolayout.
            return CGSize.zero
        }
    }

    // MARK: - Subviews

    let timerHeight: CGFloat = 24
    private func updateContent() {
        AssertIsOnMainThread()

        let imageName = isViewOnceEnabled ? "view-once-24" : "view-infinite-24"
        viewOnceButton.setTemplateImageName(imageName, tintColor: Theme.darkThemePrimaryColor)

        textContainer.isHidden = isViewOnceEnabled
        viewOnceWrapper.isHidden = !options.contains(.canToggleViewOnce)

        updateHeight(textView: textView)

        showViewOnceTooltipIfNecessary()

        updateRecipientNames()
    }

    lazy var textView: MentionTextView = {
        let textView = buildTextView()

        textView.returnKeyType = .done
        textView.scrollIndicatorInsets = UIEdgeInsets(top: 5, left: 0, bottom: 5, right: 3)
        textView.mentionDelegate = self

        return textView
    }()

    private let placeholderText = NSLocalizedString("MESSAGE_TEXT_FIELD_PLACEHOLDER", comment: "placeholder text for the editable message field")

    private lazy var placeholderTextView: UITextView = {
        let placeholderTextView = buildTextView()

        placeholderTextView.text = placeholderText
        placeholderTextView.isEditable = false
        placeholderTextView.textContainer.maximumNumberOfLines = 1
        placeholderTextView.textContainer.lineBreakMode = .byTruncatingTail
        placeholderTextView.textColor = .ows_whiteAlpha60

        return placeholderTextView
    }()

    private lazy var recipientNamesLabelScrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.isHidden = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.contentInset = UIEdgeInsets(top: kToolbarMargin, leading: 16, bottom: 0, trailing: 16)

        scrollView.addSubview(recipientNamesLabel)
        recipientNamesLabel.autoPinEdgesToSuperviewEdges()
        recipientNamesLabel.autoMatch(.height, to: .height, of: scrollView, withOffset: -kToolbarMargin)

        return scrollView
    }()

    private lazy var recipientNamesLabel: UILabel = {
        let label = UILabel()
        label.font = .ows_dynamicTypeBody2
        label.textColor = Theme.darkThemePrimaryColor

        label.setContentHuggingLow()

        return label
    }()

    private lazy var viewOnceRecipientNamesLabelScrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.isHidden = true
        scrollView.showsHorizontalScrollIndicator = false

        scrollView.addSubview(viewOnceRecipientNamesLabel)
        viewOnceRecipientNamesLabel.autoPinEdgesToSuperviewEdges()
        viewOnceRecipientNamesLabel.autoMatch(.width, to: .width, of: scrollView, withOffset: 0, relation: .greaterThanOrEqual)
        viewOnceRecipientNamesLabel.autoMatch(.height, to: .height, of: scrollView)

        return scrollView
    }()

    private lazy var viewOnceRecipientNamesLabel: UILabel = {
        let label = UILabel()
        label.font = .ows_dynamicTypeBody2
        label.textColor = Theme.darkThemePrimaryColor
        label.textAlignment = .center

        label.setContentHuggingLow()

        return label
    }()

    private lazy var textContainer: UIView = {
        let textContainer = UIView()
        let textBorder = UIView()
        textContainer.addSubview(textBorder)
        let inset = (kMinToolbarItemHeight - kMinTextViewHeight) / 2
        textBorder.autoPinEdgesToSuperviewEdges(with: UIEdgeInsets(top: 0, leading: 0, bottom: inset, trailing: 0))

        textBorder.layer.borderColor = Theme.darkThemePrimaryColor.cgColor
        textBorder.layer.borderWidth = CGHairlineWidthFraction(1.4)
        textBorder.layer.cornerRadius = kMinTextViewHeight / 2
        textBorder.clipsToBounds = true

        textBorder.addSubview(placeholderTextView)
        placeholderTextView.autoPinEdgesToSuperviewEdges()

        textBorder.addSubview(textView)
        textView.autoPinEdgesToSuperviewEdges()

        return textContainer
    }()

    private func buildTextView() -> MentionTextView {
        let textView = AttachmentTextView()

        textView.keyboardAppearance = Theme.darkThemeKeyboardAppearance
        textView.backgroundColor = .clear
        textView.tintColor = Theme.darkThemePrimaryColor

        let textViewFont = UIFont.ows_dynamicTypeBody
        textView.font = textViewFont
        textView.textColor = Theme.darkThemePrimaryColor

        // Check the system font size and increase text inset accordingly
        // to keep the text vertically centered
        textView.updateVerticalInsetsForDynamicBodyType(defaultInsets: 7)
        textView.textContainerInset.left = 7
        textView.textContainerInset.right = 7

        return textView
    }

    private let viewOnceButton = OWSButton()

    private let viewOnceSpacer = UIView.hStretchingSpacer()

    // MARK: - Actions

    @objc
    func didTapSend() {
        assert(attachmentTextToolbarDelegate != nil)

        textView.acceptAutocorrectSuggestion()
        attachmentTextToolbarDelegate?.attachmentTextToolbarDidTapSend(self)
    }

    @objc
    func didTapViewOnceMessagesButton() {
        AssertIsOnMainThread()

        // Toggle value.
        attachmentTextToolbarDelegate?.isViewOnceEnabled = !isViewOnceEnabled
        preferences.setWasViewOnceTooltipShown()

        attachmentTextToolbarDelegate?.attachmentTextToolbarDidViewOnce(self)

        if isViewOnceEnabled { textView.resignFirstResponder() }

        updateContent()
    }

    // MARK: - MentionTextViewDelegate

    func textViewDidBeginTypingMention(_ textView: MentionTextView) {
        attachmentTextToolbarDelegate?.textViewDidBeginTypingMention(textView)
    }

    func textViewDidEndTypingMention(_ textView: MentionTextView) {
        attachmentTextToolbarDelegate?.textViewDidEndTypingMention(textView)
    }

    func textViewMentionPickerParentView(_ textView: MentionTextView) -> UIView? {
        return attachmentTextToolbarDelegate?.textViewMentionPickerParentView(textView)
    }

    func textViewMentionPickerReferenceView(_ textView: MentionTextView) -> UIView? {
        return attachmentTextToolbarDelegate?.textViewMentionPickerReferenceView(textView)
    }

    func textViewMentionPickerPossibleAddresses(_ textView: MentionTextView) -> [SignalServiceAddress] {
        return attachmentTextToolbarDelegate?.textViewMentionPickerPossibleAddresses(textView) ?? []
    }

    func textView(_ textView: MentionTextView, didDeleteMention mention: Mention) {}

    func textView(_ textView: MentionTextView, shouldResolveMentionForAddress address: SignalServiceAddress) -> Bool {
        owsAssertDebug(attachmentTextToolbarDelegate != nil)
        return attachmentTextToolbarDelegate?.textView(textView, shouldResolveMentionForAddress: address) ?? false
    }

    func textViewMentionStyle(_ textView: MentionTextView) -> Mention.Style {
        return .composingAttachment
    }

    // MARK: - UITextViewDelegate

    public func textViewDidChange(_ textView: UITextView) {
        updateHeight(textView: textView)
        attachmentTextToolbarDelegate?.attachmentTextToolbarDidChange(self)
        updatePlaceholderTextViewVisibility()
    }

    public func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        // Though we can wrap the text, we don't want to encourage multline captions, plus a "done" button
        // allows the user to get the keyboard out of the way while in the attachment approval view.
        if text == "\n" {
            textView.resignFirstResponder()
            return false
        } else {
            return true
        }
    }

    public func textViewDidBeginEditing(_ textView: UITextView) {
        attachmentTextToolbarDelegate?.attachmentTextToolbarDidBeginEditing(self)
        updatePlaceholderTextViewVisibility()
    }

    public func textViewDidEndEditing(_ textView: UITextView) {
        attachmentTextToolbarDelegate?.attachmentTextToolbarDidEndEditing(self)
        updatePlaceholderTextViewVisibility()
    }

    // MARK: - Helpers

    func updatePlaceholderTextViewVisibility() {
        let isHidden: Bool = {
            guard let text = self.textView.text else {
                return false
            }

            guard text.count > 0 else {
                return false
            }

            return true
        }()

        placeholderTextView.isHidden = isHidden
    }

    func updateRecipientNames() {
        viewOnceSpacer.isHidden = !isViewOnceEnabled || recipientNames.count > 0
        viewOnceRecipientNamesLabelScrollView.isHidden = !isViewOnceEnabled || recipientNames.isEmpty
        recipientNamesLabelScrollView.isHidden = isViewOnceEnabled || recipientNames.count < 2

        switch recipientNames.count {
        case 0:
            placeholderTextView.text = placeholderText
        case 1:
            let messageToText = String(
                format: NSLocalizedString(
                    "ATTACHMENT_APPROVAL_MESSAGE_TO_FORMAT",
                    comment: "Placeholder text indicating who this attachment will be sent to. Embeds: {{recipient name}}"
                ), recipientNames[0]
            )
            placeholderTextView.text = messageToText
            viewOnceRecipientNamesLabel.text = messageToText
        default:
            let namesList = recipientNames.joined(separator: ", ")
            placeholderTextView.text = placeholderText
            recipientNamesLabel.text = namesList
            viewOnceRecipientNamesLabel.text = namesList
        }
    }

    private func updateHeight(textView: UITextView) {
        guard let textViewHeightConstraint = textViewHeightConstraint else {
            owsFailDebug("Missing constraint.")
            return
        }

        // compute new height assuming width is unchanged
        let currentSize = textView.frame.size
        let textViewHeight = clampedTextViewHeight(fixedWidth: currentSize.width)

        if textViewHeightConstraint.constant != textViewHeight {
            Logger.debug("TextView height changed: \(textViewHeightConstraint.constant) -> \(textViewHeight)")
            textViewHeightConstraint.constant = textViewHeight
            invalidateIntrinsicContentSize()
        }
        textViewHeightConstraint.isActive = !isViewOnceEnabled
    }

    private func clampedTextViewHeight(fixedWidth: CGFloat) -> CGFloat {
        let contentSize = textView.sizeThatFits(CGSize(width: fixedWidth, height: CGFloat.greatestFiniteMagnitude))
        return CGFloatClamp(contentSize.height, kMinTextViewHeight, maxTextViewHeight)
    }

    // MARK: - Helpers

    // The tooltip lies outside this view's bounds, so we
    // need to special-case the hit testing so that it can
    // intercept touches within its bounds.
    @objc
    public override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        if let viewOnceTooltip = self.viewOnceTooltip {
            let tooltipFrame = convert(viewOnceTooltip.bounds, from: viewOnceTooltip)
            if tooltipFrame.contains(point) {
                return true
            }
        }
        return super.point(inside: point, with: event)
    }

    private var shouldShowViewOnceTooltip: Bool {
        guard !isViewOnceEnabled else {
            return false
        }
        guard !preferences.wasViewOnceTooltipShown() else {
            return false
        }
        return true
    }

    private var viewOnceTooltip: UIView?

    // Show the tooltip if a) it should be shown b) isn't already showing.
    private func showViewOnceTooltipIfNecessary() {
        guard shouldShowViewOnceTooltip else {
            return
        }
        guard nil == viewOnceTooltip else {
            // Already showing the tooltip.
            return
        }
        guard !viewOnceButton.isHidden && !viewOnceWrapper.isHidden else {
            return
        }
        let tooltip = ViewOnceTooltip.present(fromView: self, widthReferenceView: self, tailReferenceView: viewOnceButton) { [weak self] in
            self?.removeViewOnceTooltip()
        }
        viewOnceTooltip = tooltip

        DispatchQueue.global().async {
            self.preferences.setWasViewOnceTooltipShown()

            DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 5) { [weak self] in
                self?.removeViewOnceTooltip()
            }
        }
    }

    private func removeViewOnceTooltip() {
        viewOnceTooltip?.removeFromSuperview()
        viewOnceTooltip = nil
    }
}
