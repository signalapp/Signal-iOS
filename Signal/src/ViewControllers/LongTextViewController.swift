//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit
import SignalMessaging

@objc
public class LongTextViewController: OWSViewController {

    // MARK: Properties

    let viewItem: ConversationViewItem

    let messageBody: String

    var messageTextView: UITextView!

    // MARK: Initializers

    @available(*, unavailable, message:"use other constructor instead.")
    public required init?(coder aDecoder: NSCoder) {
        fatalError("\(#function) is unimplemented.")
    }

    @objc
    public required init(viewItem: ConversationViewItem) {
        self.viewItem = viewItem

        self.messageBody = LongTextViewController.displayableText(viewItem: viewItem)

        super.init(nibName: nil, bundle: nil)
    }

    private class func displayableText(viewItem: ConversationViewItem) -> String {
        guard viewItem.hasBodyText else {
            return ""
        }
        guard let displayableText = viewItem.displayableBodyText() else {
            return ""
        }
        let messageBody = displayableText.fullText
        return messageBody
    }

    // MARK: View Lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()

        self.navigationItem.title = NSLocalizedString("LONG_TEXT_VIEW_TITLE",
                                                      comment: "Title for the 'long text message' view.")

        createViews()

        self.messageTextView.contentOffset = CGPoint(x: 0, y: self.messageTextView.contentInset.top)
    }

    // MARK: - Create Views

    private func createViews() {
        view.backgroundColor = Theme.backgroundColor

        let messageTextView = OWSTextView()
        self.messageTextView = messageTextView
        messageTextView.font = UIFont.ows_dynamicTypeBody
        messageTextView.backgroundColor = Theme.backgroundColor
        messageTextView.isOpaque = true
        messageTextView.isEditable = false
        messageTextView.isSelectable = true
        messageTextView.isScrollEnabled = true
        messageTextView.showsHorizontalScrollIndicator = false
        messageTextView.showsVerticalScrollIndicator = true
        messageTextView.isUserInteractionEnabled = true
        messageTextView.textColor = Theme.primaryColor
        messageTextView.dataDetectorTypes = OWSAllowedDataDetectorTypes
        messageTextView.text = messageBody

        view.addSubview(messageTextView)
        messageTextView.autoPinEdge(toSuperviewEdge: .top)
        messageTextView.autoPinEdge(toSuperviewMargin: .leading)
        messageTextView.autoPinEdge(toSuperviewMargin: .trailing)

        let footer = UIToolbar()
        view.addSubview(footer)
        footer.autoPinWidthToSuperview()
        footer.autoPinEdge(.top, to: .bottom, of: messageTextView)
        footer.autoPin(toBottomLayoutGuideOf: self, withInset: 0)

        footer.items = [
            UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
            UIBarButtonItem(barButtonSystemItem: .action, target: self, action: #selector(shareButtonPressed)),
            UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        ]
    }

    // MARK: - Actions

    @objc func shareButtonPressed() {
        AttachmentSharing.showShareUI(forText: messageBody)
    }
}
