//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit
import SignalMessaging

protocol LongTextViewDelegate: class {
    func longTextViewMessageWasDeleted(_ longTextViewController: LongTextViewController)
}

// MARK: -
public class LongTextViewController: OWSViewController {

    // MARK: - Properties

    weak var delegate: LongTextViewDelegate?

    let itemViewModel: CVItemViewModelImpl

    var messageTextView: UITextView!

    var displayableText: DisplayableText? { itemViewModel.displayableBodyText }
    var fullAttributedText: NSAttributedString { displayableText?.fullAttributedText ?? NSAttributedString() }

    // MARK: Initializers

    public required init(itemViewModel: CVItemViewModelImpl) {
        self.itemViewModel = itemViewModel
        super.init()
    }

    // MARK: View Lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.title = NSLocalizedString("LONG_TEXT_VIEW_TITLE",
                                                 comment: "Title for the 'long text message' view.")

        createViews()

        self.messageTextView.contentOffset = CGPoint(x: 0, y: self.messageTextView.contentInset.top)

        databaseStorage.appendUIDatabaseSnapshotDelegate(self)
    }

    // MARK: -

    private func refreshContent() {
        AssertIsOnMainThread()

        let uniqueId = itemViewModel.interaction.uniqueId

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
            let mutableText = NSMutableAttributedString(attributedString: fullAttributedText)
            mutableText.addAttributes(
                [.font: UIFont.ows_dynamicTypeBody, .foregroundColor: Theme.primaryTextColor],
                range: mutableText.entireRange
            )

            // Mentions have a custom style on the long-text view
            // that differs from the message, so we re-color them here.
            Mention.updateWithStyle(.longMessageView, in: mutableText)

            messageTextView.attributedText = mutableText
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

    @objc
    func shareButtonPressed(_ sender: UIBarButtonItem) {
        AttachmentSharing.showShareUI(forText: fullAttributedText.string, sender: sender)
    }

    @objc
    func forwardButtonPressed() {
        ForwardMessageNavigationController.present(for: itemViewModel, from: self, delegate: self)
    }
}

// MARK: -

extension LongTextViewController: UIDatabaseSnapshotDelegate {

    public func uiDatabaseSnapshotWillUpdate() {
        AssertIsOnMainThread()
    }

    public func uiDatabaseSnapshotDidUpdate(databaseChanges: UIDatabaseChanges) {
        AssertIsOnMainThread()

        guard databaseChanges.didUpdate(interaction: itemViewModel.interaction) else {
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
    public func forwardMessageFlowDidComplete(itemViewModel: CVItemViewModelImpl,
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
        guard thread.uniqueId != itemViewModel.interaction.uniqueThreadId else {
            return
        }
        SignalApp.shared().presentConversation(for: thread, animated: true)
    }
}
