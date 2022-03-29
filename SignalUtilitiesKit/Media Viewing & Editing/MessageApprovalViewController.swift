//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import SessionUIKit

@objc
public protocol MessageApprovalViewControllerDelegate: class {
    func messageApproval(_ messageApproval: MessageApprovalViewController, didApproveMessage messageText: String)
    func messageApprovalDidCancel(_ messageApproval: MessageApprovalViewController)
}

@objc
public class MessageApprovalViewController: OWSViewController, UITextViewDelegate {

    weak var delegate: MessageApprovalViewControllerDelegate?

    // MARK: Properties

    let thread: TSThread
    let initialMessageText: String

    private(set) var textView: UITextView!
    private var sendButton: UIBarButtonItem!

    // MARK: Initializers

    @available(*, unavailable, message:"use attachment: constructor instead.")
    required public init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    @objc
    required public init(messageText: String, thread: TSThread, delegate: MessageApprovalViewControllerDelegate) {
        self.initialMessageText = messageText
        self.thread = thread
        self.delegate = delegate

        super.init(nibName: nil, bundle: nil)
    }

    // MARK: View Lifecycle

    override public func viewDidLoad() {
        super.viewDidLoad()

        self.navigationItem.title = NSLocalizedString("MESSAGE_APPROVAL_DIALOG_TITLE",
                                                      comment: "Title for the 'message approval' dialog.")

        self.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .stop, target: self, action: #selector(cancelPressed))
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

    // MARK: - Create Views

    public override func loadView() {

        self.view = UIView.container()
        self.view.backgroundColor = Colors.navigationBarBackground

        // Recipient Row
        let recipientRow = createRecipientRow()
        view.addSubview(recipientRow)
        recipientRow.autoPinEdge(toSuperviewSafeArea: .leading)
        recipientRow.autoPinEdge(toSuperviewSafeArea: .trailing)
        recipientRow.autoPinEdge(.bottom, to: .bottom, of: view)

        // Text View
        textView = OWSTextView()
        textView.delegate = self
        textView.backgroundColor = Colors.navigationBarBackground
        textView.textColor = Colors.text
        textView.font = UIFont.ows_dynamicTypeBody
        textView.text = self.initialMessageText
        textView.contentInset = UIEdgeInsets(top: 0.0, left: 0.0, bottom: 0.0, right: 0.0)
        textView.textContainerInset = UIEdgeInsets(top: 10.0, left: 10.0, bottom: 10.0, right: 10.0)
        view.addSubview(textView)
        textView.autoPinEdge(toSuperviewSafeArea: .leading)
        textView.autoPinEdge(toSuperviewSafeArea: .trailing)
        textView.autoPinEdge(.top, to: .bottom, of: recipientRow)
        textView.autoPinEdge(.bottom, to: .bottom, of: view)
    }

    private func createRecipientRow() -> UIView {
        let recipientRow = UIView.container()
        recipientRow.backgroundColor = UIColor.lokiDarkestGray()

        // Hairline borders should be 1 pixel, not 1 point.
        let borderThickness = 1.0 / UIScreen.main.scale
        let borderColor = UIColor(white: 0.5, alpha: 1)

        let topBorder = UIView.container()
        topBorder.backgroundColor = borderColor
        recipientRow.addSubview(topBorder)
        topBorder.autoPinWidthToSuperview()
        topBorder.autoPinTopToSuperviewMargin()
        topBorder.autoSetDimension(.height, toSize: borderThickness)

        let bottomBorder = UIView.container()
        bottomBorder.backgroundColor = borderColor
        recipientRow.addSubview(bottomBorder)
        bottomBorder.autoPinWidthToSuperview()
        bottomBorder.autoPinBottomToSuperviewMargin()
        bottomBorder.autoSetDimension(.height, toSize: borderThickness)

        let font = UIFont.ows_regularFont(withSize: ScaleFromIPhone5To7Plus(14.0, 18.0))
        let hSpacing = CGFloat(10)
        let hMargin = CGFloat(15)
        let vSpacing = CGFloat(5)
        let vMargin = CGFloat(10)

        let toLabel = UILabel()
        toLabel.text = NSLocalizedString("MESSAGE_APPROVAL_RECIPIENT_LABEL",
                                         comment: "Label for the recipient name in the 'message approval' dialog.")
        toLabel.textColor = Colors.separator
        toLabel.font = font
        recipientRow.addSubview(toLabel)

        let nameLabel = UILabel()
        nameLabel.textColor = Colors.text
        nameLabel.font = font
        nameLabel.lineBreakMode = .byTruncatingTail
        recipientRow.addSubview(nameLabel)

        toLabel.autoPinLeadingToSuperviewMargin(withInset: hMargin)
        toLabel.setContentHuggingHorizontalHigh()
        toLabel.setCompressionResistanceHorizontalHigh()
        toLabel.autoAlignAxis(.horizontal, toSameAxisOf: nameLabel)

        nameLabel.autoPinLeading(toTrailingEdgeOf: toLabel, offset: hSpacing)
        nameLabel.autoPinTrailingToSuperviewMargin(withInset: hMargin)
        nameLabel.setContentHuggingHorizontalLow()
        nameLabel.setCompressionResistanceHorizontalLow()
        nameLabel.autoPinTopToSuperviewMargin(withInset: vMargin)

        if let groupThread = self.thread as? TSGroupThread {
            let groupName = (groupThread.name().count > 0
            ? groupThread.name()
                : MessageStrings.newGroupDefaultTitle)

            nameLabel.text = groupName
            nameLabel.autoPinBottomToSuperviewMargin(withInset: vMargin)

            return recipientRow
        }
        guard let contactThread = self.thread as? TSContactThread else {
            owsFailDebug("Unexpected thread type")
            return recipientRow
        }

        let publicKey = contactThread.contactSessionID()
        nameLabel.text = Storage.shared.getContact(with: publicKey)?.displayName(for: .regular) ?? publicKey
        nameLabel.textColor = Colors.text

        if let profileName = self.profileName(contactThread: contactThread) {
            // If there's a profile name worth showing, add it as a second line below the name.
            let profileNameLabel = UILabel()
            profileNameLabel.textColor = Colors.separator
            profileNameLabel.font = font
            profileNameLabel.text = profileName
            profileNameLabel.lineBreakMode = .byTruncatingTail
            recipientRow.addSubview(profileNameLabel)
            profileNameLabel.autoPinEdge(.top, to: .bottom, of: nameLabel, withOffset: vSpacing)
            profileNameLabel.autoPinLeading(toTrailingEdgeOf: toLabel, offset: hSpacing)
            profileNameLabel.autoPinTrailingToSuperviewMargin(withInset: hMargin)
            profileNameLabel.setContentHuggingHorizontalLow()
            profileNameLabel.setCompressionResistanceHorizontalLow()
            profileNameLabel.autoPinBottomToSuperviewMargin(withInset: vMargin)
        } else {
            nameLabel.autoPinBottomToSuperviewMargin(withInset: vMargin)
        }

        return recipientRow
    }

    private func profileName(contactThread: TSContactThread) -> String? {
        let publicKey = contactThread.contactSessionID()
        return Storage.shared.getContact(with: publicKey)?.displayName(for: .regular) ?? publicKey
    }

    // MARK: - Event Handlers

    @objc func cancelPressed(sender: UIButton) {
        delegate?.messageApprovalDidCancel(self)
    }

    @objc func sendPressed(sender: UIButton) {
        delegate?.messageApproval(self, didApproveMessage: self.textView.text)
    }

    // MARK: - UITextViewDelegate

    public func textViewDidChange(_ textView: UITextView) {
        updateSendButton()
    }
}
