//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
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

    private var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
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

    @objc
    public required init(viewItem: ConversationViewItem) {
        self.viewItem = viewItem
        super.init()
    }

    // MARK: View Lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()

        self.navigationItem.title = NSLocalizedString("LONG_TEXT_VIEW_TITLE",
                                                      comment: "Title for the 'long text message' view.")

        createViews()

        self.messageTextView.contentOffset = CGPoint(x: 0, y: self.messageTextView.contentInset.top)

        databaseStorage.appendUIDatabaseSnapshotDelegate(self)
    }

    // MARK: -

    private func refreshContent() {
        AssertIsOnMainThread()

        let uniqueId = self.viewItem.interaction.uniqueId

        do {
            try databaseStorage.uiReadThrows { transaction in
                guard TSInteraction.anyFetch(uniqueId: uniqueId, transaction: transaction) != nil else {
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
        messageTextView.textColor = Theme.primaryTextColor
        if let displayableText = displayableText {
            messageTextView.text = fullText
            messageTextView.textAlignment = displayableText.fullTextNaturalAlignment
            messageTextView.ensureShouldLinkifyText(displayableText.shouldAllowLinkification)
        } else {
            owsFailDebug("displayableText was unexpectedly nil")
            messageTextView.text = ""
        }

        let linkTextAttributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key.foregroundColor: Theme.primaryTextColor,
            NSAttributedString.Key.underlineColor: Theme.primaryTextColor,
            NSAttributedString.Key.underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        messageTextView.linkTextAttributes = linkTextAttributes

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
        footer.tintColor = Theme.primaryIconColor

        footer.items = [
            UIBarButtonItem(
                image: Theme.iconImage(.messageActionShare),
                style: .plain,
                target: self,
                action: #selector(shareButtonPressed)
            ),
            UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
            UIBarButtonItem(
                image: Theme.iconImage(.messageActionForward),
                style: .plain,
                target: self,
                action: #selector(forwardButtonPressed)
            )
        ]
    }

    // MARK: - Actions

    @objc func shareButtonPressed(_ sender: UIBarButtonItem) {
        AttachmentSharing.showShareUI(forText: fullText, sender: sender)
    }

    @objc func forwardButtonPressed() {
        ForwardMessageNavigationController.present(for: viewItem, from: self, delegate: self)
    }
}

// MARK: -

extension LongTextViewController: UIDatabaseSnapshotDelegate {

    public func uiDatabaseSnapshotWillUpdate() {
        AssertIsOnMainThread()
    }

    public func uiDatabaseSnapshotDidUpdate(databaseChanges: UIDatabaseChanges) {
        AssertIsOnMainThread()

        guard databaseChanges.didUpdate(interaction: self.viewItem.interaction) else {
            return
        }
        assert(databaseChanges.didUpdateInteractions)

        refreshContent()
    }

    public func uiDatabaseSnapshotDidUpdateExternally() {
        AssertIsOnMainThread()

        refreshContent()
    }

    public func uiDatabaseSnapshotDidReset() {
        AssertIsOnMainThread()

        refreshContent()
    }
}

// MARK: -

extension LongTextViewController: ForwardMessageDelegate {
    public func forwardMessageFlowDidComplete(viewItem: ConversationViewItem,
                                              threads: [TSThread]) {
        dismiss(animated: true) {
            self.didForwardMessage(threads: threads)
        }
    }

    public func forwardMessageFlowDidCancel() {
        dismiss(animated: true)
    }

    func didForwardMessage(threads: [TSThread]) {
        guard threads.count == 1 else {
            return
        }
        guard let thread = threads.first else {
            owsFailDebug("Missing thread.")
            return
        }
        guard thread.uniqueId != viewItem.interaction.uniqueThreadId else {
            return
        }
        SignalApp.shared().presentConversation(for: thread, animated: true)
    }
}
