//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalMessaging
import SignalUI

protocol LongTextViewDelegate: AnyObject {
    func longTextViewMessageWasDeleted(_ longTextViewController: LongTextViewController)
}

// MARK: -
public class LongTextViewController: OWSViewController {

    // MARK: - Properties

    weak var delegate: LongTextViewDelegate?

    let itemViewModel: CVItemViewModelImpl
    let threadViewModel: ThreadViewModel
    let spoilerState: SpoilerRenderState

    var messageTextView: UITextView!
    let footer = UIToolbar.clear()

    private var linkItems: [CVTextLabel.Item]?

    var displayableText: DisplayableText? { itemViewModel.displayableBodyText }

    // MARK: Initializers

    public required init(
        itemViewModel: CVItemViewModelImpl,
        threadViewModel: ThreadViewModel,
        spoilerState: SpoilerRenderState
    ) {
        self.itemViewModel = itemViewModel
        self.threadViewModel = threadViewModel
        self.spoilerState = spoilerState
        super.init()
    }

    // MARK: View Lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.title = OWSLocalizedString("LONG_TEXT_VIEW_TITLE",
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

        let displayConfig = HydratedMessageBody.DisplayConfiguration.longMessageView(
            revealedSpoilerIds: spoilerState.revealState.revealedSpoilerIds(
                interactionIdentifier: .fromInteraction(itemViewModel.interaction)
            )
        )

        messageTextViewSpoilerConfig.animator = self.spoilerState.animator
        messageTextViewSpoilerConfig.text = displayableText?.fullTextValue
        messageTextViewSpoilerConfig.displayConfig = displayConfig

        if let displayableText = displayableText {
            let baseAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.dynamicTypeBody,
                .foregroundColor: Theme.primaryTextColor
            ]

            let mutableText: NSMutableAttributedString
            switch displayableText.fullTextValue {
            case .text(let text):
                mutableText = NSMutableAttributedString(string: text, attributes: baseAttrs)
            case .attributedText(let text):
                mutableText = NSMutableAttributedString(attributedString: text)
                mutableText.addAttributesToEntireString(baseAttrs)
            case .messageBody(let messageBody):
                let attrString = messageBody.asAttributedStringForDisplay(
                    config: displayConfig,
                    isDarkThemeEnabled: Theme.isDarkThemeEnabled
                )
                mutableText = (attrString as? NSMutableAttributedString) ?? NSMutableAttributedString(attributedString: attrString)
            }

            let hasPendingMessageRequest = databaseStorage.read { transaction in
                itemViewModel.thread.hasPendingMessageRequest(transaction: transaction.unwrapGrdbRead)
            }
            CVComponentBodyText.configureTextView(
                messageTextView,
                interaction: itemViewModel.interaction,
                displayableText: displayableText
            )

            let items = CVComponentBodyText.detectItems(
                text: displayableText,
                hasPendingMessageRequest: hasPendingMessageRequest,
                shouldAllowLinkification: displayableText.shouldAllowLinkification,
                textWasTruncated: false,
                revealedSpoilerIds: displayConfig.style.revealedIds,
                interactionUniqueId: itemViewModel.interaction.uniqueId,
                interactionIdentifier: .fromInteraction(itemViewModel.interaction)
            )

            CVTextLabel.linkifyData(
                attributedText: mutableText,
                linkifyStyle: .linkAttribute,
                items: items
            )
            messageTextView.attributedText = mutableText
            messageTextView.textAlignment = displayableText.fullTextNaturalAlignment
            self.linkItems = items

            if items.isEmpty.negated {
                messageTextView.addGestureRecognizer(UITapGestureRecognizer(
                    target: self,
                    action: #selector(didTapMessageTextView)
                ))
            }
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
                image: Theme.iconImage(.buttonShare),
                style: .plain,
                target: self,
                action: #selector(shareButtonPressed)
            ),
            UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
            UIBarButtonItem(
                image: Theme.iconImage(.buttonForward),
                style: .plain,
                target: self,
                action: #selector(forwardButtonPressed)
            )
        ]

        loadContent()
    }

    // MARK: - Spoiler Animation

    private lazy var messageTextViewSpoilerConfig = SpoilerableTextConfig.Builder(isViewVisible: true) {
        didSet {
            messageTextViewSpoilerAnimator.updateAnimationState(messageTextViewSpoilerConfig)
        }
    }

    private lazy var messageTextViewSpoilerAnimator: SpoilerableTextViewAnimator = {
        let animator = SpoilerableTextViewAnimator(textView: messageTextView)
        animator.updateAnimationState(messageTextViewSpoilerConfig)
        return animator
    }()

    // MARK: - Actions

    @objc
    private func shareButtonPressed(_ sender: UIBarButtonItem) {
        guard let displayableText else {
            return
        }
        let shareText: String
        switch displayableText.fullTextValue {
        case .text(let text):
            shareText = text
        case .attributedText(let string):
            shareText = string.string
        case .messageBody(let messageBody):
            shareText = messageBody.asPlaintext()
        }
        AttachmentSharing.showShareUI(for: shareText, sender: sender)
    }

    @objc
    private func forwardButtonPressed() {
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

    @objc
    private func didTapMessageTextView(_ sender: UIGestureRecognizer) {
        guard let linkItems else {
            return
        }
        let location = sender.location(in: messageTextView)

        guard let characterIndex = messageTextView.characterIndex(of: location) else {
            return
        }

        for item in linkItems {
            if item.range.contains(characterIndex) {
                switch item {
                case .referencedUser:
                    owsFailDebug("Should not have referenced user in long message body.")
                    return
                case .dataItem(let dataItem):
                    UIApplication.shared.open(dataItem.url, options: [:], completionHandler: nil)
                    return
                case .mention(let mentionItem):
                    ImpactHapticFeedback.impactOccurred(style: .light)

                    var groupViewHelper: GroupViewHelper?
                    if threadViewModel.isGroupThread {
                        groupViewHelper = GroupViewHelper(threadViewModel: threadViewModel)
                        groupViewHelper!.delegate = self
                    }

                    let address = SignalServiceAddress(uuid: mentionItem.mentionUUID)
                    let actionSheet = MemberActionSheet(
                        address: address,
                        groupViewHelper: groupViewHelper,
                        spoilerState: spoilerState
                    )
                    actionSheet.present(from: self)
                    return
                case .unrevealedSpoiler(let unrevealedSpoiler):
                    self.spoilerState.revealState.setSpoilerRevealed(
                        withID: unrevealedSpoiler.spoilerId,
                        interactionIdentifier: unrevealedSpoiler.interactionIdentifier
                    )
                    self.loadContent()
                    return
                }
            }
        }
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

// MARK: -

extension LongTextViewController: GroupViewHelperDelegate {
    var currentGroupModel: TSGroupModel? {
        return (threadViewModel.threadRecord as? TSGroupThread)?.groupModel
    }

    func groupViewHelperDidUpdateGroup() {}

    var fromViewController: UIViewController? {
        return self
    }
}
