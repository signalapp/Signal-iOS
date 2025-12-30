//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

protocol LongTextViewDelegate: AnyObject {
    func longTextViewMessageWasDeleted(_ longTextViewController: LongTextViewController)
}

class LongTextViewController: OWSViewController {

    // MARK: - Properties

    weak var delegate: LongTextViewDelegate?

    private let itemViewModel: CVItemViewModelImpl
    private let threadViewModel: ThreadViewModel
    private let spoilerState: SpoilerRenderState

    private let textView: UITextView = {
        let textView = OWSTextView()
        textView.font = UIFont.dynamicTypeBody
        textView.textColor = .Signal.label
        textView.backgroundColor = .Signal.background
        textView.isOpaque = true
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = true
        textView.showsHorizontalScrollIndicator = false
        textView.showsVerticalScrollIndicator = true
        textView.isUserInteractionEnabled = true
        return textView
    }()

    private lazy var toolbar: UIToolbar = {
        let toolbar = UIToolbar()
        toolbar.items = [
            UIBarButtonItem(
                image: Theme.iconImage(.buttonShare),
                primaryAction: UIAction { [weak self] _ in
                    self?.shareButtonPressed()
                },
            ),

            .flexibleSpace(),

            UIBarButtonItem(
                image: Theme.iconImage(.buttonForward),
                primaryAction: UIAction { [weak self] _ in
                    self?.forwardButtonPressed()
                },
            ),
        ]
        if #unavailable(iOS 26) {
            toolbar.tintColor = Theme.primaryIconColor
            toolbar.setShadowImage(UIImage(), forToolbarPosition: .any)
        }
        return toolbar
    }()

    private var linkItems: [CVTextLabel.Item]?

    private var displayableText: DisplayableText? { itemViewModel.displayableBodyText }

    // MARK: - UIViewController

    init(
        itemViewModel: CVItemViewModelImpl,
        threadViewModel: ThreadViewModel,
        spoilerState: SpoilerRenderState,
    ) {
        self.itemViewModel = itemViewModel
        self.threadViewModel = threadViewModel
        self.spoilerState = spoilerState
        super.init()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.title = OWSLocalizedString(
            "LONG_TEXT_VIEW_TITLE",
            comment: "Title for the 'long text message' view.",
        )
        view.backgroundColor = .Signal.background

        view.addSubview(textView)
        view.addSubview(toolbar)
        textView.translatesAutoresizingMaskIntoConstraints = false
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: view.topAnchor),
            textView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            toolbar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])

        if #available(iOS 26, *) {
            let interaction = UIScrollEdgeElementContainerInteraction()
            interaction.edge = .bottom
            interaction.scrollView = textView
            toolbar.addInteraction(interaction)
        }

        loadContent()

        if #available(iOS 17, *) {
            // Modern alternative to `themeDidChange`.
            textView.registerForTraitChanges([UITraitUserInterfaceStyle.self, UITraitPreferredContentSizeCategory.self]) { [weak self] (view: UIView, _) in
                self?.loadContent()
            }
        }

        DependenciesBridge.shared.databaseChangeObserver.appendDatabaseChangeDelegate(self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        // Scroll to top.
        textView.contentOffset = CGPoint(x: 0, y: textView.contentInset.top)
    }

    override func viewLayoutMarginsDidChange() {
        super.viewLayoutMarginsDidChange()

        // Text view is constrained to root view's left and right safe areas.
        // Readable content guide's left and right margins include respective safe areas.
        // We need to subtract safe area margins from readable content guide's margins to get proper text alignment.
        // Since we use view's and layout guide's frames here make sure to only operate
        // with "left" and "right" insets and don't mix with "leading" / "trailing".
        textView.textContainerInset.left = view.readableContentGuide.layoutFrame.minX - view.safeAreaInsets.left
        textView.textContainerInset.right = view.bounds.maxX - view.readableContentGuide.layoutFrame.maxX - view.safeAreaInsets.left
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        // UIKit adjusts bottom inset for the safe area height, so we just need to account for toolbar height.
        let bottomInset = toolbar.frame.height
        textView.textContainerInset.bottom = bottomInset + 16
        textView.verticalScrollIndicatorInsets.bottom = bottomInset
    }

    override func themeDidChange() {
        super.themeDidChange()

        if #unavailable(iOS 26) {
            toolbar.tintColor = Theme.primaryIconColor
        }
        if #unavailable(iOS 17) {
            loadContent()
        }
    }

    override func contentSizeCategoryDidChange() {
        super.contentSizeCategoryDidChange()
        if #unavailable(iOS 17) {
            loadContent()
        }
    }

    // MARK: - Content

    private func loadContent() {
        let displayConfig = HydratedMessageBody.DisplayConfiguration.longMessageView(
            revealedSpoilerIds: spoilerState.revealState.revealedSpoilerIds(
                interactionIdentifier: .fromInteraction(itemViewModel.interaction),
            ),
        )

        messageTextViewSpoilerConfig.animationManager = spoilerState.animationManager
        messageTextViewSpoilerConfig.text = displayableText?.fullTextValue
        messageTextViewSpoilerConfig.displayConfig = displayConfig

        guard let displayableText else {
            owsFailDebug("displayableText was unexpectedly nil")
            textView.text = ""
            return
        }

        let textColor: UIColor
        if #available(iOS 17, *) {
            textColor = UIColor.Signal.label.resolvedColor(with: textView.traitCollection)
        } else {
            textColor = Theme.primaryTextColor
        }

        let baseAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.dynamicTypeBody,
            .foregroundColor: textColor,
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
                isDarkThemeEnabled: Theme.isDarkThemeEnabled,
            )
            mutableText = (attrString as? NSMutableAttributedString) ?? NSMutableAttributedString(attributedString: attrString)
        }

        let hasPendingMessageRequest = SSKEnvironment.shared.databaseStorageRef.read { transaction in
            itemViewModel.thread.hasPendingMessageRequest(transaction: transaction)
        }
        CVComponentBodyText.configureTextView(
            textView,
            interaction: itemViewModel.interaction,
            displayableText: displayableText,
        )

        let items = CVComponentBodyText.detectItems(
            text: displayableText,
            hasPendingMessageRequest: hasPendingMessageRequest,
            shouldAllowLinkification: displayableText.shouldAllowLinkification,
            textWasTruncated: false,
            revealedSpoilerIds: displayConfig.style.revealedIds,
            interactionUniqueId: itemViewModel.interaction.uniqueId,
            interactionIdentifier: .fromInteraction(itemViewModel.interaction),
        )

        CVTextLabel.linkifyData(
            attributedText: mutableText,
            linkifyStyle: .linkAttribute,
            items: items,
        )
        textView.attributedText = mutableText
        textView.textAlignment = displayableText.fullTextNaturalAlignment
        linkItems = items

        if items.isEmpty.negated {
            textView.addGestureRecognizer(UITapGestureRecognizer(
                target: self,
                action: #selector(didTapMessageTextView),
            ))
        }

        textView.linkTextAttributes = [
            .foregroundColor: textColor,
            .underlineColor: textColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ]
    }

    private func checkIfMessageWasDeleted() {
        AssertIsOnMainThread()

        let uniqueId = itemViewModel.interaction.uniqueId
        let messageWasDeleted = SSKEnvironment.shared.databaseStorageRef.read {
            TSInteraction.anyFetch(uniqueId: uniqueId, transaction: $0) == nil
        }
        guard messageWasDeleted else { return }

        Logger.error("Message was deleted")
        DispatchQueue.main.async {
            self.delegate?.longTextViewMessageWasDeleted(self)
        }
    }

    // MARK: - Spoiler Animation

    private lazy var messageTextViewSpoilerConfig = SpoilerableTextConfig.Builder(isViewVisible: true) {
        didSet {
            messageTextViewSpoilerAnimator.updateAnimationState(messageTextViewSpoilerConfig)
        }
    }

    private lazy var messageTextViewSpoilerAnimator: SpoilerableTextViewAnimator = {
        let animator = SpoilerableTextViewAnimator(textView: textView)
        animator.updateAnimationState(messageTextViewSpoilerConfig)
        return animator
    }()

    // MARK: - Actions

    private func shareButtonPressed() {
        guard let displayableText else { return }

        let shareText: String
        switch displayableText.fullTextValue {
        case .text(let text):
            shareText = text
        case .attributedText(let string):
            shareText = string.string
        case .messageBody(let messageBody):
            shareText = messageBody.asPlaintext()
        }
        AttachmentSharing.showShareUI(for: shareText, sender: toolbar.items?.first)
    }

    private func forwardButtonPressed() {
        // Only forward text.
        let selectionType: CVSelectionType = (itemViewModel.componentState.hasPrimaryAndSecondaryContentForSelection
            ? .secondaryContent
            : .allContent)
        let selectionItem = CVSelectionItem(
            interactionId: itemViewModel.interaction.uniqueId,
            interactionType: itemViewModel.interaction.interactionType,
            isForwardable: true,
            selectionType: selectionType,
        )
        ForwardMessageViewController.present(
            forSelectionItems: [selectionItem],
            from: self,
            delegate: self,
        )
    }

    @objc
    private func didTapMessageTextView(_ sender: UIGestureRecognizer) {
        guard let linkItems else {
            return
        }
        let location = sender.location(in: textView)

        guard let characterIndex = textView.characterIndex(of: location) else {
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

                    let address = SignalServiceAddress(mentionItem.mentionAci)
                    ProfileSheetSheetCoordinator(
                        address: address,
                        groupViewHelper: groupViewHelper,
                        spoilerState: spoilerState,
                    )
                    .presentAppropriateSheet(from: self)
                    return
                case .unrevealedSpoiler(let unrevealedSpoiler):
                    self.spoilerState.revealState.setSpoilerRevealed(
                        withID: unrevealedSpoiler.spoilerId,
                        interactionIdentifier: unrevealedSpoiler.interactionIdentifier,
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

    func databaseChangesDidUpdate(databaseChanges: DatabaseChanges) {
        guard databaseChanges.didUpdate(interaction: itemViewModel.interaction) else {
            return
        }
        assert(databaseChanges.didUpdateInteractions)

        checkIfMessageWasDeleted()
    }

    func databaseChangesDidUpdateExternally() {
        checkIfMessageWasDeleted()
    }

    func databaseChangesDidReset() {
        checkIfMessageWasDeleted()
    }
}

// MARK: -

extension LongTextViewController: ForwardMessageDelegate {
    func forwardMessageFlowDidComplete(
        items: [ForwardMessageItem],
        recipientThreads: [TSThread],
    ) {
        dismiss(animated: true) {
            ForwardMessageViewController.finalizeForward(
                items: items,
                recipientThreads: recipientThreads,
                fromViewController: self,
            )
        }
    }

    func forwardMessageFlowDidCancel() {
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
