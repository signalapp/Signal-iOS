//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public protocol MessageApprovalViewControllerDelegate: class {
    func messageApproval(_ messageApproval: MessageApprovalViewController, didApproveMessage messageText: String)
    func messageApprovalDidCancel(_ messageApproval: MessageApprovalViewController)
}

@objc
public class MessageApprovalViewController: OWSViewController, UITextViewDelegate {

    let TAG = "[MessageApprovalViewController]"
    weak var delegate: MessageApprovalViewControllerDelegate?

    // MARK: Properties

    let initialMessageText: String

    private(set) var textView: UITextView!
    private(set) var topToolbar: UIToolbar!

    // MARK: Initializers

    @available(*, unavailable, message:"use attachment: constructor instead.")
    required public init?(coder aDecoder: NSCoder) {
        fatalError("unimplemented")
    }

    @objc
    required public init(messageText: String, delegate: MessageApprovalViewControllerDelegate) {
        self.initialMessageText = messageText
        self.delegate = delegate

        super.init(nibName: nil, bundle: nil)
    }

    // MARK: View Lifecycle

    override public func viewDidLoad() {
        super.viewDidLoad()
        self.navigationItem.title = NSLocalizedString("MESSAGE_APPROVAL_DIALOG_TITLE",
                                                      comment: "Title for the 'message approval' dialog.")
    }

    private func updateToolbar() {
        var items = [UIBarButtonItem]()

        let cancelButton = UIBarButtonItem(barButtonSystemItem: .stop, target: self, action: #selector(cancelPressed))
        items.append(cancelButton)

        if textView.text.count > 0 {
            let spacer = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
            items.append(spacer)
            let sendButton = UIBarButtonItem(title: NSLocalizedString("SEND_BUTTON_TITLE",
                                                                      comment:"Label for the send button in the conversation view."),
                                             style:.plain,
                                             target: self,
                                             action: #selector(sendPressed))
            items.append(sendButton)
        }

        topToolbar.items = items
    }

    // MARK: - Create Views

    public override func loadView() {

        self.view = UIView()
        self.view.backgroundColor = UIColor.white

        // Top Toolbar
        topToolbar = UIToolbar()
        topToolbar.backgroundColor = UIColor.ows_inputToolbarBackground
        self.view.addSubview(topToolbar)
        topToolbar.autoPinWidthToSuperview()
        topToolbar.autoPin(toTopLayoutGuideOf: self, withInset: 0)
        topToolbar.setContentHuggingVerticalHigh()
        topToolbar.setCompressionResistanceVerticalHigh()

        // Text View
        textView = UITextView()
        textView.delegate = self
        textView.backgroundColor = UIColor.white
        textView.textColor = UIColor.black
        textView.font = UIFont.ows_dynamicTypeBody()
        textView.text = self.initialMessageText
        view.addSubview(textView)
        textView.autoPinWidthToSuperview()
        textView.autoPinEdge(.top, to: .bottom, of: topToolbar)
        textView.autoPin(toBottomLayoutGuideOf: self, withInset: 0)

        updateToolbar()
    }

    // MARK: - Event Handlers

    func cancelPressed(sender: UIButton) {
        delegate?.messageApprovalDidCancel(self)
    }

    func sendPressed(sender: UIButton) {
        delegate?.messageApproval(self, didApproveMessage: self.textView.text)
    }

    // MARK: - UITextViewDelegate

    public func textViewDidChange(_ textView: UITextView) {
        updateToolbar()
    }
}
