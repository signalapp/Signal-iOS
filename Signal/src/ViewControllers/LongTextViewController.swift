//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit
import SignalMessaging

@objc
public protocol LongTextViewDelegate {
    @objc
    func longTextViewMessageWasDeleted(_ longTextViewController: LongTextViewController)
}

@objc
public class LongTextViewController: OWSViewController {

    // MARK: - Dependencies

    var uiDatabaseConnection: YapDatabaseConnection {
        return OWSPrimaryStorage.shared().uiDatabaseConnection
    }

    // MARK: - Properties

    @objc
    weak var delegate: LongTextViewDelegate?

    let viewItem: ConversationViewItem

    var messageTextView: UITextView!

    var displayableText: DisplayableText? {
        return viewItem.displayableBodyText
    }

    var fullText: String {
        return displayableText?.fullText ?? ""
    }

    // MARK: Initializers

    @available(*, unavailable, message:"use other constructor instead.")
    public required init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    @objc
    public required init(viewItem: ConversationViewItem) {
        self.viewItem = viewItem
        super.init(nibName: nil, bundle: nil)
    }

    // MARK: View Lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()

        self.navigationItem.title = NSLocalizedString("LONG_TEXT_VIEW_TITLE",
                                                      comment: "Title for the 'long text message' view.")

        createViews()

        self.messageTextView.contentOffset = CGPoint(x: 0, y: self.messageTextView.contentInset.top)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(uiDatabaseDidUpdate),
                                               name: .OWSUIDatabaseConnectionDidUpdate,
                                               object: OWSPrimaryStorage.shared().dbNotificationObject)
    }

    // MARK: - DB

    @objc internal func uiDatabaseDidUpdate(notification: NSNotification) {
        AssertIsOnMainThread()

        guard let notifications = notification.userInfo?[OWSUIDatabaseConnectionNotificationsKey] as? [Notification] else {
            owsFailDebug("notifications was unexpectedly nil")
            return
        }

        guard let uniqueId = self.viewItem.interaction.uniqueId else {
            Logger.error("Message is missing uniqueId.")
            return
        }

        guard self.uiDatabaseConnection.hasChange(forKey: uniqueId,
                                                  inCollection: TSInteraction.collection(),
                                                  in: notifications) else {
                                                    Logger.debug("No relevant changes.")
                                                    return
        }

        do {
            try uiDatabaseConnection.read { transaction in
                guard TSInteraction.fetch(uniqueId: uniqueId, transaction: transaction) != nil else {
                    Logger.error("Message was deleted")
                    throw LongTextViewError.messageWasDeleted
                }
            }
        } catch LongTextViewError.messageWasDeleted {
            DispatchQueue.main.async {
                self.delegate?.longTextViewMessageWasDeleted(self)
            }
        } catch {
            owsFailDebug("unexpected error: \(error)")

        }
    }

    enum LongTextViewError: Error {
        case messageWasDeleted
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
        if let displayableText = displayableText {
            messageTextView.text = fullText
            messageTextView.ensureShouldLinkifyText(displayableText.shouldAllowLinkification)
        } else {
            owsFailDebug("displayableText was unexpectedly nil")
            messageTextView.text = ""
        }

        // RADAR #18669
        // https://github.com/lionheart/openradar-mirror/issues/18669
        //
        // UITextView’s linkTextAttributes property has type [String : Any]! but should be [NSAttributedStringKey : Any]! in Swift 4.
        let linkTextAttributes: [String: Any] = [
            NSAttributedString.Key.foregroundColor.rawValue: Theme.primaryColor,
            NSAttributedString.Key.underlineColor.rawValue: Theme.primaryColor,
            NSAttributedString.Key.underlineStyle.rawValue: NSUnderlineStyle.single.rawValue
        ]
        messageTextView.linkTextAttributes = convertToOptionalNSAttributedStringKeyDictionary(linkTextAttributes)

        view.addSubview(messageTextView)
        messageTextView.autoPinEdge(toSuperviewEdge: .top)
        messageTextView.autoPinEdge(toSuperviewEdge: .leading)
        messageTextView.autoPinEdge(toSuperviewEdge: .trailing)
        messageTextView.textContainerInset = UIEdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)

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
        AttachmentSharing.showShareUI(forText: fullText)
    }
}

// Helper function inserted by Swift 4.2 migrator.
private func convertToOptionalNSAttributedStringKeyDictionary(_ input: [String: Any]?) -> [NSAttributedString.Key: Any]? {
	guard let input = input else { return nil }
	return Dictionary(uniqueKeysWithValues: input.map { key, value in (NSAttributedString.Key(rawValue: key), value)})
}
