//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public protocol TextApprovalViewControllerDelegate: class {
    func textApproval(_ textApproval: TextApprovalViewController, didApproveMessage messageText: String)

    func textApprovalDidCancel(_ textApproval: TextApprovalViewController)

    func textApprovalCustomTitle(_ textApproval: TextApprovalViewController) -> String?

    func textApprovalRecipientsDescription(_ textApproval: TextApprovalViewController) -> String?

    func textApprovalMode(_ textApproval: TextApprovalViewController) -> ApprovalMode
}

// MARK: -

@objc
public class TextApprovalViewController: OWSViewController, UITextViewDelegate {

    @objc
    public weak var delegate: TextApprovalViewControllerDelegate?

    // MARK: - Properties

    private let initialMessageText: String

    private(set) var textView: UITextView!
    private let footerView = ApprovalFooterView()
    private var footerViewBottomConstraint: NSLayoutConstraint?

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
    required public init(messageText: String) {
        self.initialMessageText = messageText

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
            self.navigationItem.title = NSLocalizedString("MESSAGE_APPROVAL_DIALOG_TITLE",
                                                          comment: "Title for the 'message approval' dialog.")
        }

        self.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancelPressed))

        footerView.delegate = self
    }

    private func updateSendButton() {
        guard textView.text.count > 0 else {
            footerView.isHidden = true
            return
        }
        guard let recipientsDescription = delegate?.textApprovalRecipientsDescription(self) else {
            footerView.isHidden = true
            return
        }
        footerView.setNamesText(recipientsDescription, animated: false)
        footerView.isHidden = false
    }

    override public func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        updateSendButton()

        textView.becomeFirstResponder()
    }

    // MARK: - Create Views

    public override func loadView() {

        self.view = UIView.container()
        self.view.backgroundColor = Theme.backgroundColor

        // Text View
        textView = OWSTextView()
        textView.delegate = self
        textView.backgroundColor = Theme.backgroundColor
        textView.textColor = Theme.primaryTextColor
        textView.font = UIFont.ows_dynamicTypeBody
        textView.text = self.initialMessageText
        textView.contentInset = UIEdgeInsets(top: 0.0, left: 0.0, bottom: 0.0, right: 0.0)
        textView.textContainerInset = UIEdgeInsets(top: 10.0, left: 10.0, bottom: 10.0, right: 10.0)
        view.addSubview(textView)
        textView.autoPinEdge(toSuperviewSafeArea: .leading)
        textView.autoPinEdge(toSuperviewSafeArea: .trailing)
        textView.autoPin(toTopLayoutGuideOf: self, withInset: 0)

        view.addSubview(footerView)
        footerView.autoPinWidthToSuperview()
        footerView.autoPinEdge(.top, to: .bottom, of: textView)
        footerViewBottomConstraint = footerView.autoPinEdge(toSuperviewEdge: .bottom)
    }

    // MARK: - Event Handlers

    @objc func cancelPressed(sender: UIButton) {
        delegate?.textApprovalDidCancel(self)
    }

    // MARK: - UITextViewDelegate

    public func textViewDidChange(_ textView: UITextView) {
        updateSendButton()
    }
}

// MARK: -

extension TextApprovalViewController: ApprovalFooterDelegate {
    public func approvalFooterDelegateDidRequestProceed(_ approvalFooterView: ApprovalFooterView) {
        delegate?.textApproval(self, didApproveMessage: self.textView.text)
    }

    public func approvalMode(_ approvalFooterView: ApprovalFooterView) -> ApprovalMode {
        return approvalMode
    }
}

extension TextApprovalViewController: InputAccessoryViewPlaceholderDelegate {
    func inputAccessoryPlaceholderKeyboardIsPresenting(animationDuration: TimeInterval, animationCurve: UIView.AnimationCurve) {
        handleKeyboardStateChange(animationDuration: animationDuration, animationCurve: animationCurve)
    }

    func inputAccessoryPlaceholderKeyboardIsDismissing(animationDuration: TimeInterval, animationCurve: UIView.AnimationCurve) {
        handleKeyboardStateChange(animationDuration: animationDuration, animationCurve: animationCurve)
    }

    func inputAccessoryPlaceholderKeyboardIsDismissingInteractively() {
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
        footerViewBottomConstraint?.constant = -inputAccessoryPlaceholder.keyboardOverlap

        // We always want to apply the new bottom bar position immediately,
        // as this only happens during animations (interactive or otherwise)
        footerView.superview?.layoutIfNeeded()
    }
}
