//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc
public protocol TextApprovalViewControllerDelegate: AnyObject {
    func textApproval(_ textApproval: TextApprovalViewController, didApproveMessage messageBody: MessageBody?, linkPreviewDraft: OWSLinkPreviewDraft?)

    func textApprovalDidCancel(_ textApproval: TextApprovalViewController)

    func textApprovalCustomTitle(_ textApproval: TextApprovalViewController) -> String?

    func textApprovalRecipientsDescription(_ textApproval: TextApprovalViewController) -> String?

    func textApprovalMode(_ textApproval: TextApprovalViewController) -> ApprovalMode
}

// MARK: -

@objc
public class TextApprovalViewController: OWSViewController, MentionTextViewDelegate {
    @objc
    public weak var delegate: TextApprovalViewControllerDelegate?

    // MARK: - Properties

    private let initialMessageBody: MessageBody

    private let textView = MentionTextView()
    private let footerView = ApprovalFooterView()
    private var bottomConstraint: NSLayoutConstraint?

    private lazy var inputAccessoryPlaceholder: InputAccessoryViewPlaceholder = {
        let placeholder = InputAccessoryViewPlaceholder()
        placeholder.delegate = self
        placeholder.referenceView = view
        return placeholder
    }()

    private var approvalMode: ApprovalMode {
        guard let delegate = delegate else {
            return .send
        }
        return delegate.textApprovalMode(self)
    }

    // MARK: - Initializers

    @objc
    required public init(messageBody: MessageBody) {
        self.initialMessageBody = messageBody

        super.init()
    }

    // MARK: - UIViewController

    public override var canBecomeFirstResponder: Bool {
        return true
    }

    var currentInputAcccessoryView: UIView?

    public override var inputAccessoryView: UIView? {
        return inputAccessoryPlaceholder
    }

    // MARK: - View Lifecycle

    override public func viewDidLoad() {
        super.viewDidLoad()

        if let title = delegate?.textApprovalCustomTitle(self) {
            self.navigationItem.title = title
        } else {
            self.navigationItem.title = OWSLocalizedString("MESSAGE_APPROVAL_DIALOG_TITLE",
                                                          comment: "Title for the 'message approval' dialog.")
        }

        self.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancelPressed))

        footerView.delegate = self

        // Don't allow interactive dismissal.
        if #available(iOS 13, *) { isModalInPresentation = true }
    }

    private func updateSendButton() {
        guard
            !textView.text.isEmpty,
            let recipientsDescription = delegate?.textApprovalRecipientsDescription(self)
        else {
            footerView.isHidden = true
            return
        }
        footerView.setNamesText(recipientsDescription, animated: false)
        footerView.isHidden = false
    }

    override public func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        updateSendButton()
        updateLinkPreviewIfNecessary()

        textView.becomeFirstResponder()
    }

    // MARK: - Link Previews

    private var wasLinkPreviewCancelled = false
    private lazy var linkPreviewView: LinkPreviewView = {
        let linkPreviewView = LinkPreviewView(draftDelegate: self)
        linkPreviewView.isHidden = true
        return linkPreviewView
    }()

    private var currentPreviewUrl: URL? {
        didSet {
            guard currentPreviewUrl != oldValue else { return }
            guard let previewUrl = currentPreviewUrl else { return }

            let linkPreviewView = self.linkPreviewView
            linkPreviewView.configureForNonCVC(state: LinkPreviewLoading(linkType: .preview),
                                               isDraft: true)
            linkPreviewView.isHidden = false

            linkPreviewManager.fetchLinkPreview(for: previewUrl).done(on: .main) { [weak self] draft in
                guard let self = self else { return }
                guard self.currentPreviewUrl == previewUrl else { return }
                linkPreviewView.configureForNonCVC(state: LinkPreviewDraft(linkPreviewDraft: draft),
                                                   isDraft: true)
            }.catch { [weak self] _ in
                self?.clearLinkPreview()
            }
        }
    }

    private func updateLinkPreviewIfNecessary() {
        let trimmedText = textView.text.ows_stripped()
        guard !trimmedText.isEmpty else { return clearLinkPreview() }
        guard !wasLinkPreviewCancelled else { return clearLinkPreview() }

        let isOversizedText = trimmedText.lengthOfBytes(using: .utf8) >= kOversizeTextMessageSizeThreshold
        guard !isOversizedText else { return clearLinkPreview() }

        guard let previewUrl = linkPreviewManager.findFirstValidUrl(in: trimmedText, bypassSettingsCheck: false) else { return clearLinkPreview() }

        currentPreviewUrl = previewUrl
    }

    private func clearLinkPreview() {
        currentPreviewUrl = nil
        linkPreviewView.isHidden = true
        linkPreviewView.reset()
    }

    // MARK: - Create Views

    public override func loadView() {

        self.view = UIView.container()
        self.view.backgroundColor = Theme.backgroundColor

        let stackView = UIStackView(arrangedSubviews: [linkPreviewView, textView, footerView])
        stackView.axis = .vertical
        view.addSubview(stackView)
        stackView.autoPin(toTopLayoutGuideOf: self, withInset: 0)
        stackView.autoPinEdge(toSuperviewSafeArea: .leading)
        stackView.autoPinEdge(toSuperviewSafeArea: .trailing)
        bottomConstraint = stackView.autoPinEdge(toSuperviewEdge: .bottom)

        // Text View
        textView.mentionDelegate = self
        textView.backgroundColor = Theme.backgroundColor
        textView.textColor = Theme.primaryTextColor
        textView.font = UIFont.ows_dynamicTypeBody
        textView.messageBody = self.initialMessageBody
        textView.contentInset = UIEdgeInsets(top: 0.0, left: 0.0, bottom: 0.0, right: 0.0)
        textView.textContainerInset = UIEdgeInsets(top: 10.0, left: 10.0, bottom: 10.0, right: 10.0)
    }

    // MARK: - Event Handlers

    @objc
    func cancelPressed(sender: UIButton) {
        delegate?.textApprovalDidCancel(self)
    }

    // MARK: - UITextViewDelegate

    public func textViewDidChange(_ textView: UITextView) {
        updateSendButton()
        updateLinkPreviewIfNecessary()
    }

    public func textViewDidBeginTypingMention(_ textView: MentionTextView) {}

    public func textViewDidEndTypingMention(_ textView: MentionTextView) {}

    public func textViewMentionPickerParentView(_ textView: MentionTextView) -> UIView? {
        return nil
    }

    public func textViewMentionPickerReferenceView(_ textView: MentionTextView) -> UIView? {
        return nil
    }

    public func textViewMentionPickerPossibleAddresses(_ textView: MentionTextView) -> [SignalServiceAddress] {
        return []
    }

    public func textViewMentionStyle(_ textView: MentionTextView) -> Mention.Style {
        return .composing
    }

    public func textView(_ textView: MentionTextView, didDeleteMention: Mention) {}
}

// MARK: -

extension TextApprovalViewController: ApprovalFooterDelegate {
    public func approvalFooterDelegateDidRequestProceed(_ approvalFooterView: ApprovalFooterView) {
        let linkPreviewDraft: OWSLinkPreviewDraft?
        if !wasLinkPreviewCancelled, let draftState = linkPreviewView.state as? LinkPreviewDraft {
            linkPreviewDraft = draftState.linkPreviewDraft
        } else {
            linkPreviewDraft = nil
        }
        delegate?.textApproval(self, didApproveMessage: self.textView.messageBody, linkPreviewDraft: linkPreviewDraft)
    }

    public func approvalMode(_ approvalFooterView: ApprovalFooterView) -> ApprovalMode {
        return approvalMode
    }

    public func approvalFooterDidBeginEditingText() {}
}

// MARK: -

extension TextApprovalViewController: InputAccessoryViewPlaceholderDelegate {
    public func inputAccessoryPlaceholderKeyboardIsPresenting(animationDuration: TimeInterval, animationCurve: UIView.AnimationCurve) {
        handleKeyboardStateChange(animationDuration: animationDuration, animationCurve: animationCurve)
    }

    public func inputAccessoryPlaceholderKeyboardDidPresent() {
        updateFooterViewPosition()
    }

    public func inputAccessoryPlaceholderKeyboardIsDismissing(animationDuration: TimeInterval, animationCurve: UIView.AnimationCurve) {
        handleKeyboardStateChange(animationDuration: animationDuration, animationCurve: animationCurve)
    }

    public func inputAccessoryPlaceholderKeyboardDidDismiss() {
        updateFooterViewPosition()
    }

    public func inputAccessoryPlaceholderKeyboardIsDismissingInteractively() {
        updateFooterViewPosition()
    }

    func handleKeyboardStateChange(animationDuration: TimeInterval, animationCurve: UIView.AnimationCurve) {
        guard animationDuration > 0 else { return updateFooterViewPosition() }

        UIView.beginAnimations("keyboardStateChange", context: nil)
        UIView.setAnimationBeginsFromCurrentState(true)
        UIView.setAnimationCurve(animationCurve)
        UIView.setAnimationDuration(animationDuration)
        updateFooterViewPosition()
        UIView.commitAnimations()
    }

    func updateFooterViewPosition() {
        bottomConstraint?.constant = -inputAccessoryPlaceholder.keyboardOverlap

        // We always want to apply the new bottom bar position immediately,
        // as this only happens during animations (interactive or otherwise)
        view.layoutIfNeeded()
    }
}

// MARK: -

extension TextApprovalViewController: LinkPreviewViewDraftDelegate {
    public func linkPreviewDidCancel() {
        clearLinkPreview()
        wasLinkPreviewCancelled = true
    }

    public func linkPreviewCanCancel() -> Bool {
        return true
    }
}
