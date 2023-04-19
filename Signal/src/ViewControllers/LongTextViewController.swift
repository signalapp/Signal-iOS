//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import SignalMessaging

protocol LongTextViewDelegate: AnyObject {
    func longTextViewMessageWasDeleted(_ longTextViewController: LongTextViewController)
}

// MARK: -
public class LongTextViewController: OWSViewController {

    // MARK: - Properties

    weak var delegate: LongTextViewDelegate?

    let itemViewModel: CVItemViewModelImpl

    var messageTextView: UITextView!
    let footer = UIToolbar.clear()

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

        databaseStorage.appendDatabaseChangeDelegate(self)
    }

    public override func themeDidChange() {
        super.themeDidChange()

        loadContent()
    }

    public func loadContent() {
        super.themeDidChange()

        view.backgroundColor = Theme.backgroundColor
        messageTextView.backgroundColor = Theme.backgroundColor
        messageTextView.textColor = Theme.primaryTextColor
        footer.tintColor = Theme.primaryIconColor

        if let displayableText = displayableText {
            let mutableText = NSMutableAttributedString(attributedString: fullAttributedText)
            mutableText.addAttributes(
                [.font: UIFont.dynamicTypeBody, .foregroundColor: Theme.primaryTextColor],
                range: mutableText.entireRange
            )

            // Mentions have a custom style on the long-text view
            // that differs from the message, so we re-color them here.
            Mention.updateWithStyle(.longMessageView, in: mutableText)

            let hasPendingMessageRequest = databaseStorage.read { transaction in
                itemViewModel.thread.hasPendingMessageRequest(transaction: transaction.unwrapGrdbRead)
            }
            CVComponentBodyText.configureTextView(messageTextView,
                                                  interaction: itemViewModel.interaction,
                                                  displayableText: displayableText)
            CVComponentBodyText.linkifyData(attributedText: mutableText,
                                            linkifyStyle: .linkAttribute,
                                            hasPendingMessageRequest: hasPendingMessageRequest,
                                            shouldAllowLinkification: displayableText.shouldAllowLinkification,
                                            textWasTruncated: false)

            messageTextView.attributedText = mutableText
            messageTextView.textAlignment = displayableText.fullTextNaturalAlignment
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
    }

    // MARK: -

    private func refreshContent() {
        AssertIsOnMainThread()

        let uniqueId = itemViewModel.interaction.uniqueId
        let messageWasDeleted = databaseStorage.read {
            TSInteraction.anyFetch(uniqueId: uniqueId, transaction: $0) == nil
        }
        guard messageWasDeleted else {
            return
        }
        Logger.error("Message was deleted")
        DispatchQueue.main.async {
            self.delegate?.longTextViewMessageWasDeleted(self)
        }
    }

    // MARK: - Create Views

    private func createViews() {
        view.backgroundColor = Theme.backgroundColor

        let messageTextView = OWSTextView()
        self.messageTextView = messageTextView
        messageTextView.font = UIFont.dynamicTypeBody
        messageTextView.backgroundColor = Theme.backgroundColor
        messageTextView.isOpaque = true
        messageTextView.isEditable = false
        messageTextView.isSelectable = true
        messageTextView.isScrollEnabled = true
        messageTextView.showsHorizontalScrollIndicator = false
        messageTextView.showsVerticalScrollIndicator = true
        messageTextView.isUserInteractionEnabled = true
        messageTextView.textColor = Theme.primaryTextColor

        view.addSubview(messageTextView)
        messageTextView.autoPinEdge(toSuperviewEdge: .top)
        messageTextView.autoPinEdge(toSuperviewEdge: .leading)
        messageTextView.autoPinEdge(toSuperviewEdge: .trailing)
        messageTextView.textContainerInset = UIEdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)

        view.addSubview(footer)
        footer.autoPinWidthToSuperview()
        footer.autoPinEdge(.top, to: .bottom, of: messageTextView)
        footer.autoPin(toBottomLayoutGuideOf: self, withInset: 0)
        footer.tintColor = Theme.primaryIconColor

        footer.items = [
            UIBarButtonItem(
                image: Theme.iconImage(.messageActionShare24),
                style: .plain,
                target: self,
                action: #selector(shareButtonPressed)
            ),
            UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
            UIBarButtonItem(
                image: Theme.iconImage(.messageActionForward24),
                style: .plain,
                target: self,
                action: #selector(forwardButtonPressed)
            )
        ]

        loadContent()
    }

    // MARK: - Actions

    @objc
    func shareButtonPressed(_ sender: UIBarButtonItem) {
        AttachmentSharing.showShareUI(forText: fullAttributedText.string, sender: sender)
    }

    @objc
    func forwardButtonPressed() {
        // Only forward text.
        let selectionType: CVSelectionType = (itemViewModel.componentState.hasPrimaryAndSecondaryContentForSelection
                                                ? .secondaryContent
                                                : .allContent)
        let selectionItem = CVSelectionItem(interactionId: itemViewModel.interaction.uniqueId,
                                            interactionType: itemViewModel.interaction.interactionType,
                                            isForwardable: true,
                                            selectionType: selectionType)
        ForwardMessageViewController.present(forSelectionItems: [selectionItem],
                                             from: self,
                                             delegate: self)
    }
}

// MARK: -

extension LongTextViewController: DatabaseChangeDelegate {

    public func databaseChangesDidUpdate(databaseChanges: DatabaseChanges) {
        AssertIsOnMainThread()

        guard databaseChanges.didUpdate(interaction: itemViewModel.interaction) else {
            return
        }
        assert(databaseChanges.didUpdateInteractions)

        refreshContent()
    }

    public func databaseChangesDidUpdateExternally() {
        AssertIsOnMainThread()

        refreshContent()
    }

    public func databaseChangesDidReset() {
        AssertIsOnMainThread()

        refreshContent()
    }
}

// MARK: -

extension LongTextViewController: ForwardMessageDelegate {
    public func forwardMessageFlowDidComplete(items: [ForwardMessageItem],
                                              recipientThreads: [TSThread]) {
        dismiss(animated: true) {
            ForwardMessageViewController.finalizeForward(items: items,
                                                         recipientThreads: recipientThreads,
                                                         fromViewController: self)
        }
    }

    public func forwardMessageFlowDidCancel() {
        dismiss(animated: true)
    }
}
