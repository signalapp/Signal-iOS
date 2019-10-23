//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public protocol TextApprovalViewControllerDelegate: class {
    func textApproval(_ textApproval: TextApprovalViewController, didApproveMessage messageText: String)
    func textApprovalDidCancel(_ textApproval: TextApprovalViewController)
}

// MARK: -

@objc
public class TextApprovalViewController: OWSViewController, UITextViewDelegate {

    weak var delegate: TextApprovalViewControllerDelegate?

    // MARK: - Properties

    let initialMessageText: String

    private(set) var textView: UITextView!
    private var sendButton: UIBarButtonItem!

    // MARK: - Initializers

    @available(*, unavailable, message:"use attachment: constructor instead.")
    required public init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    @objc
    required public init(messageText: String) {
        self.initialMessageText = messageText

        super.init(nibName: nil, bundle: nil)
    }

    // MARK: - View Lifecycle

    override public func viewDidLoad() {
        super.viewDidLoad()

        self.navigationItem.title = NSLocalizedString("MESSAGE_APPROVAL_DIALOG_TITLE",
                                                      comment: "Title for the 'message approval' dialog.")

        self.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancelPressed))
        sendButton = UIBarButtonItem(title: MessageStrings.sendButton,
                                     style: .plain,
                                     target: self,
                                     action: #selector(sendPressed))
        self.navigationItem.rightBarButtonItem = sendButton
    }

    private func updateSendButton() {
        sendButton.isEnabled = textView.text.count > 0
    }

    override public func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        updateSendButton()
    }

    // MARK: - - Create Views

    public override func loadView() {

        self.view = UIView.container()
        self.view.backgroundColor = Theme.backgroundColor

//        // Recipient Row
//        let recipientRow = createRecipientRow()
//        view.addSubview(recipientRow)
//        recipientRow.autoPinEdge(toSuperviewSafeArea: .leading)
//        recipientRow.autoPinEdge(toSuperviewSafeArea: .trailing)
//        recipientRow.autoPin(toTopLayoutGuideOf: self, withInset: 0)

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
//        textView.autoPinEdge(.top, to: .bottom, of: recipientRow)
        textView.autoPin(toBottomLayoutGuideOf: self, withInset: 0)
    }

    // MARK: - - Event Handlers

    @objc func cancelPressed(sender: UIButton) {
        delegate?.textApprovalDidCancel(self)
    }

    @objc func sendPressed(sender: UIButton) {
        delegate?.textApproval(self, didApproveMessage: self.textView.text)
    }

    // MARK: - - UITextViewDelegate

    public func textViewDidChange(_ textView: UITextView) {
        updateSendButton()
    }
}
