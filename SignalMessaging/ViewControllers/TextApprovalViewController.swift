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

    var currentInputAcccessoryView: UIView? {
        didSet {
            if oldValue != currentInputAcccessoryView {
                textView.inputAccessoryView = currentInputAcccessoryView
                textView.reloadInputViews()
                reloadInputViews()
            }
        }
    }

    public override var inputAccessoryView: UIView? {
        return currentInputAcccessoryView
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
            currentInputAcccessoryView = nil
            return
        }
        guard let recipientsDescription = delegate?.textApprovalRecipientsDescription(self) else {
            currentInputAcccessoryView = nil
            return
        }
        footerView.setNamesText(recipientsDescription, animated: false)
        currentInputAcccessoryView = footerView
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
        autoPinView(toBottomOfViewControllerOrKeyboard: textView, avoidNotch: true)
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
