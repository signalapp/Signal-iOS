//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalServiceKit
import SignalUI
import SwiftUI

class MemberLabelViewController: OWSViewController, UITextFieldDelegate, CVComponentDelegate {
    private let initialEmoji: String?
    private let initialMemberLabel: String?
    private var updatedMemberLabel: String?
    private var updatedEmoji: String?

    private lazy var addEmojiButton: UIButton = {
        let button = UIButton(
            configuration: .plain(),
            primaryAction: UIAction { [weak self] _ in self?.didTapEmojiPicker() },
        )
        button.configuration?.baseForegroundColor = .Signal.secondaryLabel
        button.configuration?.titleTextAttributesTransformer = .defaultFont(.dynamicTypeTitle3Clamped)
        button.setContentHuggingHorizontalHigh()
        button.setCompressionResistanceHorizontalHigh()
        return button
    }()

    private var previewSectionHeader: UIView?
    private var previewContainer: UIView?
    private let stackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .vertical
        return stackView
    }()

    private lazy var textField: UITextField = {
        let textField = UITextField()
        textField.placeholder = OWSLocalizedString(
            "MEMBER_LABEL_VIEW_PLACEHOLDER_TEXT",
            comment: "Placeholder text in text field where user can edit their member label.",
        )
        textField.font = .dynamicTypeBodyClamped
        textField.addAction(
            UIAction { [weak self] action in
                guard let self, let textField = action.sender as? UITextField else { return }
                self.textDidChange(textField)
            },
            for: .editingChanged,
        )
        textField.delegate = self
        return textField
    }()

    private var characterCountLabel: UILabel = {
        let label = UILabel()
        label.font = .dynamicTypeBody
        label.textColor = UIColor.Signal.tertiaryLabel.withAlphaComponent(0.3)
        label.setContentHuggingHorizontalHigh()
        label.setCompressionResistanceHigh()
        return label
    }()

    private lazy var clearButton: UIButton = {
        let button = UIButton(
            configuration: .plain(),
            primaryAction: UIAction { [weak self] _ in self?.clearButtonTapped() },
        )
        button.configuration?.image = UIImage(resource: .xCircleFillCompact)
        button.tintColor = UIColor.Signal.tertiaryLabel
        button.setContentHuggingHorizontalHigh()
        button.setCompressionResistanceHorizontalHigh()
        return button
    }()

    // Views that may be updated when thread info changes
    private var contactListView: UIView?
    private var noOtherMembersView: UIView?

    private var groupNameColors: GroupNameColors
    private var groupMemberLabelsWithoutLocalUser: [SignalServiceAddress: MemberLabelForRendering]
    private var groupModel: TSGroupModelV2
    private let db: DB
    private let contactManager: OWSContactsManager
    private let localIdentifiers: LocalIdentifiers

    weak var updateDelegate: MemberLabelCoordinator?

    private static let maxCharCount = 24
    private static let showCharacterCountMax = 9

    private var onDismiss: () -> Void

    init(
        memberLabel: String? = nil,
        emoji: String? = nil,
        groupNameColors: GroupNameColors,
        groupMemberLabelsWithoutLocalUser: [SignalServiceAddress: MemberLabelForRendering],
        groupModel: TSGroupModelV2,
        db: DB,
        contactManager: OWSContactsManager,
        localIdentifiers: LocalIdentifiers,
        onDismiss: @escaping () -> Void,
    ) {
        self.initialMemberLabel = memberLabel
        self.initialEmoji = emoji
        self.updatedMemberLabel = memberLabel
        self.updatedEmoji = emoji
        self.groupNameColors = groupNameColors
        self.groupModel = groupModel
        self.groupMemberLabelsWithoutLocalUser = groupMemberLabelsWithoutLocalUser
        self.db = db
        self.contactManager = contactManager
        self.localIdentifiers = localIdentifiers
        self.onDismiss = onDismiss

        super.init()

        view.backgroundColor = UIColor.Signal.groupedBackground
        addNavigationTitleView(groupName: groupModel.groupNameOrDefault)

        navigationItem.rightBarButtonItem = .doneButton { [weak self] in self?.didTapDone() }
        navigationItem.rightBarButtonItem?.isEnabled = false

        navigationItem.leftBarButtonItem = .cancelButton(
            dismissingFrom: self,
            hasUnsavedChanges: { [weak self] in
                guard let self else { return false }
                return updatedMemberLabel != initialMemberLabel || updatedEmoji != initialEmoji
            },
            completion: {
                onDismiss()
            },
        )

        textField.text = memberLabel
    }

    func updateWithNewThreadInfo(
        groupNameColors: GroupNameColors,
        groupMemberLabelsWithoutLocalUser: [SignalServiceAddress: MemberLabelForRendering],
        groupModel: TSGroupModelV2,
    ) {
        self.groupNameColors = groupNameColors
        self.groupModel = groupModel
        self.groupMemberLabelsWithoutLocalUser = groupMemberLabelsWithoutLocalUser

        addNavigationTitleView(groupName: groupModel.groupNameOrDefault)
        reloadMessagePreview()

        reloadGroupMembershipSection()
    }

    func addNavigationTitleView(groupName: String) {
        let titleLabel = UILabel()
        titleLabel.text = OWSLocalizedString(
            "MEMBER_LABEL_VIEW_TITLE",
            comment: "Title for a view where users can edit and preview their member label.",
        )
        titleLabel.font = .dynamicTypeSubheadline.semibold()
        titleLabel.textColor = UIColor.Signal.label
        titleLabel.textAlignment = .center

        let subtitleLabel = UILabel()
        subtitleLabel.text = groupName
        subtitleLabel.font = .dynamicTypeCaption1.semibold()
        subtitleLabel.textColor = UIColor.Signal.secondaryLabel
        subtitleLabel.textAlignment = .center

        let stackView = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        stackView.axis = .vertical
        stackView.alignment = .center

        navigationItem.titleView = stackView
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let scrollView = UIScrollView()
        scrollView.keyboardDismissMode = .onDrag
        scrollView.preservesSuperviewLayoutMargins = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        stackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 20),
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stackView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
        ])

        // Text field row.
        createInputUI()

        // Message Preview.
        reloadMessagePreview()

        // Group Members.
        // Section header is always there and is therefore added just once.
        stackView.addArrangedSubview(createSectionHeaderView(OWSLocalizedString(
            "MEMBER_LABEL_GROUP_LABELS_SECTION_TITLE",
            comment: "Section header for a list of group member labels",
        )))
        reloadGroupMembershipSection()

        textField.becomeFirstResponder()

        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard)))
    }

    @discardableResult
    private func createSectionHeaderView(_ title: String, at index: Int? = nil) -> UIView {
        // This creates a header view that looks the same as the one OWSTableViewController2
        // creates - see `buildHeaderTextView()` methods.
        let sectionTitle = UILabel()
        sectionTitle.text = title
        sectionTitle.font = OWSTableViewController2.defaultHeaderFont
        sectionTitle.textColor = OWSTableViewController2.defaultHeaderTextColor
        sectionTitle.translatesAutoresizingMaskIntoConstraints = false
        let sectionTitleContainer = UIView()
        sectionTitleContainer.directionalLayoutMargins = .init(
            top: 24,
            leading: OWSTableViewController2.defaultHeaderTextHorizontalInset,
            bottom: 12,
            trailing: OWSTableViewController2.defaultHeaderTextHorizontalInset,
        )
        sectionTitleContainer.addSubview(sectionTitle)
        NSLayoutConstraint.activate([
            sectionTitle.topAnchor.constraint(equalTo: sectionTitleContainer.layoutMarginsGuide.topAnchor),
            sectionTitle.leadingAnchor.constraint(equalTo: sectionTitleContainer.layoutMarginsGuide.leadingAnchor),
            sectionTitle.trailingAnchor.constraint(equalTo: sectionTitleContainer.layoutMarginsGuide.trailingAnchor),
            sectionTitle.bottomAnchor.constraint(equalTo: sectionTitleContainer.layoutMarginsGuide.bottomAnchor),
        ])
        return sectionTitleContainer
    }

    private func createInputUI() {
        // Helper text at the top.
        let subtitleLabel = UILabel()
        subtitleLabel.text = OWSLocalizedString(
            "MEMBER_LABEL_VIEW_SUBTITLE",
            comment: "Subtitle for a view where users can edit and preview their member label.",
        )
        subtitleLabel.numberOfLines = 0
        subtitleLabel.font = OWSTableViewController2.defaultFooterFont
        subtitleLabel.textColor = OWSTableViewController2.defaultFooterTextColor
        subtitleLabel.textAlignment = .center
        stackView.addArrangedSubview(subtitleLabel)
        stackView.setCustomSpacing(24, after: subtitleLabel)

        // Input field row.
        let textFieldStack = UIStackView(arrangedSubviews: [addEmojiButton, textField, characterCountLabel, clearButton])
        textFieldStack.backgroundColor = UIColor.Signal.tertiaryBackground
        textFieldStack.alignment = .center
        textFieldStack.spacing = 8
        textFieldStack.setCustomSpacing(0, after: addEmojiButton) // button has horizontal padding in it.
        textFieldStack.isLayoutMarginsRelativeArrangement = true
        textFieldStack.directionalLayoutMargins = .init(hMargin: 8, vMargin: 0)
        if #available(iOS 26, *) {
            textFieldStack.cornerConfiguration = .capsule()
        } else {
            textFieldStack.layer.cornerRadius = OWSTableViewController2.cellRounding
        }

        if let initialEmoji {
            addEmojiButton.configuration?.image = nil
            addEmojiButton.configuration?.title = initialEmoji
        } else {
            addEmojiButton.configuration?.title = nil
            addEmojiButton.configuration?.image = UIImage(resource: .emojiPlus)
        }

        characterCountLabel.isHidden = true
        if let count = initialMemberLabel?.count {
            characterCountLabel.text = String(Self.maxCharCount - count)
            characterCountLabel.isHidden = (Self.maxCharCount - count) > Self.showCharacterCountMax
        }

        if initialMemberLabel == nil, initialEmoji == nil {
            clearButton.isHidden = true
        }

        // min height for text field row
        textFieldStack.translatesAutoresizingMaskIntoConstraints = false
        textFieldStack.heightAnchor.constraint(greaterThanOrEqualToConstant: 52).isActive = true

        stackView.addArrangedSubview(textFieldStack)
    }

    private func buildMockConversationItem() -> CVRenderItem? {
        let attachmentContentValidator = DependenciesBridge.shared.attachmentContentValidator
        let messageBody = db.write { tx in
            attachmentContentValidator.truncatedMessageBodyForInlining(
                MessageBody(text: OWSLocalizedString(
                    "MEMBER_LABEL_VIEW_MESSAGE_PREVIEW_TEXT",
                    comment: "Text shown in the preview message bubble when a user is editing their member label.",
                ), ranges: .empty),
                tx: tx,
            )
        }

        guard
            let secretParams = try? GroupSecretParams.generate()
        else {
            return nil
        }

        var groupModelBuilder = TSGroupModelBuilder(secretParams: secretParams)
        var groupMembershipBuilder = groupModelBuilder.groupMembership.asBuilder
        if let updatedMemberLabel {
            groupMembershipBuilder.setMemberLabel(label: MemberLabel(label: updatedMemberLabel, labelEmoji: updatedEmoji), aci: localIdentifiers.aci)
        }
        groupModelBuilder.groupMembership = groupMembershipBuilder.build()

        guard let groupModel = try? groupModelBuilder.buildAsV2() else {
            return nil
        }

        let mockGroupThread = MockGroupThread(groupModel: groupModel)
        let mockMessage = MockIncomingMessage(messageBody: messageBody, thread: mockGroupThread, authorAci: localIdentifiers.aci)

        let renderItem = db.read { tx in
            let conversationStyle = ConversationStyle(
                type: .default,
                thread: mockGroupThread,
                viewWidth: view.layoutMarginsGuide.layoutFrame.width,
                hasWallpaper: false,
                shouldDimWallpaperInDarkMode: false,
                chatColor: PaletteChatColor.ultramarine.colorSetting,
            )

            return CVLoader.buildStandaloneRenderItem(
                interaction: mockMessage,
                thread: mockGroupThread,
                conversationStyle: conversationStyle,
                spoilerState: SpoilerRenderState(),
                groupNameColors: groupNameColors,
                transaction: tx,
            )
        }
        return renderItem
    }

    func messageBubblePreviewContainer(renderItem: CVRenderItem) -> UIView {
        let cellContainer = UIView()
        cellContainer.clipsToBounds = true
        cellContainer.directionalLayoutMargins = .init(
            hMargin: 0,
            vMargin: OWSTableViewController2.cellVInnerMargin,
        )
        if #available(iOS 26, *) {
            cellContainer.cornerConfiguration = .uniformCorners(radius: .fixed(OWSTableViewController2.cellRounding))
        } else {
            cellContainer.layer.cornerRadius = OWSTableViewController2.cellRounding
        }
        cellContainer.backgroundColor = .Signal.secondaryGroupedBackground

        let cellView = CVCellView()
        cellView.configure(renderItem: renderItem, componentDelegate: self)
        cellView.isCellVisible = true
        cellView.translatesAutoresizingMaskIntoConstraints = false
        cellContainer.addSubview(cellView)
        NSLayoutConstraint.activate([
            cellView.heightAnchor.constraint(equalToConstant: renderItem.cellMeasurement.cellSize.height),
            cellView.widthAnchor.constraint(equalToConstant: renderItem.cellMeasurement.cellSize.width),

            cellView.topAnchor.constraint(equalTo: cellContainer.layoutMarginsGuide.topAnchor),
            cellView.leadingAnchor.constraint(equalTo: cellContainer.layoutMarginsGuide.leadingAnchor),
            cellView.trailingAnchor.constraint(lessThanOrEqualTo: cellContainer.layoutMarginsGuide.trailingAnchor),
            cellView.bottomAnchor.constraint(equalTo: cellContainer.layoutMarginsGuide.bottomAnchor),
        ])

        return cellContainer
    }

    private func clearButtonTapped() {
        textField.text = ""
        updatedMemberLabel = nil
        updatedEmoji = nil
        addEmojiButton.configuration?.title = nil
        addEmojiButton.configuration?.image = UIImage(resource: .emojiPlus)

        reloadMessagePreview()
        reloadDoneButtonStatus()
    }

    private func didTapDone() {
        Logger.info("")
        var memberLabel: MemberLabel?
        if let updatedMemberLabel {
            memberLabel = MemberLabel(label: updatedMemberLabel, labelEmoji: updatedEmoji)
        }
        dismiss(animated: true, completion: {
            owsAssertDebug(self.updateDelegate != nil)
            self.updateDelegate?.updateLabelForLocalUser(memberLabel: memberLabel)
            self.onDismiss()
        })
    }

    private func didTapEmojiPicker() {
        let picker = EmojiPickerSheet(message: nil, allowReactionConfiguration: false) { [weak self] emoji in
            guard let emojiString = emoji?.rawValue else {
                return
            }
            self?.updatedEmoji = emojiString
            self?.addEmojiButton.configuration?.image = nil
            self?.addEmojiButton.configuration?.title = emojiString
            self?.reloadDoneButtonStatus()
            self?.reloadMessagePreview()
        }
        present(picker, animated: true)
    }

    private func reloadMessagePreview() {
        if let previewContainer {
            stackView.removeArrangedSubview(previewContainer)
            previewContainer.removeFromSuperview()
            self.previewContainer = nil
        }

        if let mockRenderItem = buildMockConversationItem() {
            if previewSectionHeader == nil {
                let previewSectionHeader = createSectionHeaderView(
                    OWSLocalizedString(
                        "MEMBER_LABEL_PREVIEW_HEADING",
                        comment: "Heading shown above the preview of a message bubble with the edited member label.",
                    ),
                    at: 2,
                )
                stackView.insertArrangedSubview(previewSectionHeader, at: 2)
                self.previewSectionHeader = previewSectionHeader
            }

            let previewContainer = messageBubblePreviewContainer(renderItem: mockRenderItem)
            stackView.insertArrangedSubview(previewContainer, at: 3)
            self.previewContainer = previewContainer
        } else {
            if let previewSectionHeader {
                stackView.removeArrangedSubview(previewSectionHeader)
            }
        }

        let count = textField.text?.count ?? 0
        let charsRemaining = Self.maxCharCount - count
        characterCountLabel.text = String(charsRemaining)
        characterCountLabel.isHidden = charsRemaining > Self.showCharacterCountMax
        characterCountLabel.textColor = charsRemaining > 5 ? .Signal.tertiaryLabel.withAlphaComponent(0.3) : .Signal.red

        if updatedMemberLabel == nil, updatedEmoji == nil {
            clearButton.isHidden = true
        } else {
            clearButton.isHidden = false
        }
    }

    private func reloadDoneButtonStatus() {
        // No change, don't allow sending.
        if initialMemberLabel == updatedMemberLabel, initialEmoji == updatedEmoji {
            navigationItem.rightBarButtonItem?.isEnabled = false
            return
        }

        // Clears member label, this is allowed.
        if updatedMemberLabel == nil, updatedEmoji == nil {
            navigationItem.rightBarButtonItem?.isEnabled = true
            return
        }

        // Don't allow emoji-only.
        if updatedMemberLabel == nil {
            navigationItem.rightBarButtonItem?.isEnabled = false
            return
        }

        navigationItem.rightBarButtonItem?.isEnabled = true
    }

    func textDidChange(_ textField: UITextField) {
        let filteredText = textField.text?.filterStringForDisplay()
        let collapsedFilteredText = filteredText?.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression,
        )

        updatedMemberLabel = collapsedFilteredText?.nilIfEmpty
        reloadDoneButtonStatus()
        reloadMessagePreview()
    }

    // MARK: - UITextFieldDelegate

    func textField(
        _ textField: UITextField,
        shouldChangeCharactersIn range: NSRange,
        replacementString string: String,
    ) -> Bool {
        TextFieldHelper.textField(
            textField,
            shouldChangeCharactersInRange: range,
            replacementString: string,
            maxByteCount: 96,
            maxGlyphCount: Self.maxCharCount,
        )
    }

    // MARK: - Group member list

    private func sortedMembers() -> [(key: SignalServiceAddress, value: MemberLabelForRendering)] {
        let allMembersSorted = db.read { tx in contactManager.sortSignalServiceAddresses(groupMemberLabelsWithoutLocalUser.keys, transaction: tx)
        }

        var membersToRender = [SignalServiceAddress]()
        let groupMembership = groupModel.groupMembership
        // Admin users are first.
        let adminMembers = allMembersSorted.filter { groupMembership.isFullMemberAndAdministrator($0) }
        membersToRender += adminMembers
        // Non-admin users are second.
        let nonAdminMembers = allMembersSorted.filter { !groupMembership.isFullMemberAndAdministrator($0) }
        membersToRender += nonAdminMembers

        return membersToRender.map { (key: $0, value: groupMemberLabelsWithoutLocalUser[$0]!) }
    }

    private func reloadGroupMembershipSection() {
        if let noOtherMembersView {
            stackView.removeArrangedSubview(noOtherMembersView)
            noOtherMembersView.removeFromSuperview()
            self.noOtherMembersView = nil
        }

        if let contactListView {
            stackView.removeArrangedSubview(contactListView)
            contactListView.removeFromSuperview()
            self.contactListView = nil
        }

        let sortedNonLocalMembers = sortedMembers()

        // No other member labels - show helper text.
        guard sortedNonLocalMembers.isEmpty == false else {
            let cellContainer = UIView()
            cellContainer.clipsToBounds = true
            cellContainer.backgroundColor = .Signal.secondaryGroupedBackground
            cellContainer.directionalLayoutMargins = .init(
                hMargin: OWSTableViewController2.cellHInnerMargin,
                vMargin: OWSTableViewController2.cellVInnerMargin,
            )
            cellContainer.translatesAutoresizingMaskIntoConstraints = false
            if #available(iOS 26, *) {
                cellContainer.cornerConfiguration = .uniformCorners(radius: .fixed(OWSTableViewController2.cellRounding))
            } else {
                cellContainer.layer.cornerRadius = OWSTableViewController2.cellRounding
            }

            let noOtherMembersLabel = UILabel()
            noOtherMembersLabel.text = OWSLocalizedString(
                "MEMBER_LABEL_NO_OTHER_GROUP_MEMBERS_HAVE_LABELS",
                comment: "Text for section that shows other group member labels, when there are none",
            )
            noOtherMembersLabel.font = .dynamicTypeSubheadlineClamped
            noOtherMembersLabel.textColor = .Signal.secondaryLabel
            noOtherMembersLabel.textAlignment = .center
            noOtherMembersLabel.numberOfLines = 0
            noOtherMembersLabel.translatesAutoresizingMaskIntoConstraints = false
            cellContainer.addSubview(noOtherMembersLabel)
            NSLayoutConstraint.activate([
                noOtherMembersLabel.topAnchor.constraint(equalTo: cellContainer.layoutMarginsGuide.topAnchor),
                noOtherMembersLabel.leadingAnchor.constraint(equalTo: cellContainer.layoutMarginsGuide.leadingAnchor),
                noOtherMembersLabel.trailingAnchor.constraint(equalTo: cellContainer.layoutMarginsGuide.trailingAnchor),
                noOtherMembersLabel.bottomAnchor.constraint(equalTo: cellContainer.layoutMarginsGuide.bottomAnchor),

                cellContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 96),
            ])
            stackView.addArrangedSubview(cellContainer)

            self.noOtherMembersView = cellContainer

            return
        }

        let vSpacing: CGFloat = 5
        let contactListStackView = UIStackView()
        contactListStackView.spacing = vSpacing
        contactListStackView.axis = .vertical
        contactListStackView.backgroundColor = .Signal.secondaryGroupedBackground
        contactListStackView.clipsToBounds = true
        contactListStackView.isLayoutMarginsRelativeArrangement = true
        contactListStackView.directionalLayoutMargins = .init(
            top: vSpacing,
            leading: OWSTableViewController2.cellHInnerMargin,
            bottom: vSpacing,
            trailing: 0, // separaators should go all way to trailing edge. cell will be put in a container.
        )
        if #available(iOS 26, *) {
            contactListStackView.cornerConfiguration = .uniformCorners(radius: .fixed(OWSTableViewController2.cellRounding))
        } else {
            contactListStackView.layer.cornerRadius = OWSTableViewController2.cellRounding
        }

        for (memberAddress, memberLabel) in sortedNonLocalMembers {
            if contactListStackView.arrangedSubviews.isEmpty == false {
                let separator = UIView()
                separator.backgroundColor = .Signal.opaqueSeparator
                separator.translatesAutoresizingMaskIntoConstraints = false
                separator.heightAnchor.constraint(equalToConstant: hairlineWidth).isActive = true
                contactListStackView.addArrangedSubview(separator)
            }

            let cell = ContactCellView()
            SSKEnvironment.shared.databaseStorageRef.read { tx in
                let isSystemContact = SSKEnvironment.shared.contactManagerRef.fetchSignalAccount(
                    for: memberAddress,
                    transaction: tx,
                ) != nil

                var configuration = ContactCellView.Configuration(address: memberAddress, localUserDisplayMode: .asLocalUser)
                configuration.memberLabel = memberLabel
                configuration.shouldShowContactIcon = isSystemContact
                cell.configure(configuration: configuration, transaction: tx)

                // We need trailing margin, but only for cells, not separators.
                let cellContainer = UIView()
                cell.translatesAutoresizingMaskIntoConstraints = false
                cellContainer.addSubview(cell)
                NSLayoutConstraint.activate([
                    cell.topAnchor.constraint(equalTo: cellContainer.topAnchor),
                    cell.leadingAnchor.constraint(equalTo: cellContainer.leadingAnchor),
                    cell.trailingAnchor.constraint(
                        equalTo: cellContainer.trailingAnchor,
                        constant: -OWSTableViewController2.cellHInnerMargin,
                    ),
                    cell.bottomAnchor.constraint(equalTo: cellContainer.bottomAnchor),
                ])

                contactListStackView.addArrangedSubview(cellContainer)
            }
        }

        stackView.addArrangedSubview(contactListStackView)
        self.contactListView = contactListStackView
    }

    // MARK: -

    @objc
    private func dismissKeyboard() {
        view.endEditing(true)
    }

    // MARK: - CVComponentDelegate

    var spoilerState: SignalUI.SpoilerRenderState {
        return SpoilerRenderState()
    }

    func enqueueReload() {}

    func enqueueReloadWithoutCaches() {}

    func didTapBodyTextItem(_ item: CVTextLabel.Item) {}

    func didLongPressBodyTextItem(_ item: CVTextLabel.Item) {}

    func didTapSystemMessageItem(_ item: CVTextLabel.Item) {}

    func didTapCollapseSet(collapseSetId: String) {}

    func didDoubleTapTextViewItem(_ itemViewModel: CVItemViewModelImpl) {}

    func didLongPressTextViewItem(
        _ cell: CVCell,
        itemViewModel: CVItemViewModelImpl,
        shouldAllowMessageSendActions: Bool,
    ) {}

    func didLongPressMediaViewItem(
        _ cell: CVCell,
        itemViewModel: CVItemViewModelImpl,
        shouldAllowMessageSendActions: Bool,
    ) {}

    func didLongPressQuote(
        _ cell: CVCell,
        itemViewModel: CVItemViewModelImpl,
        shouldAllowMessageSendActions: Bool,
    ) {}

    func didLongPressSystemMessage(
        _ cell: CVCell,
        itemViewModel: CVItemViewModelImpl,
    ) {}

    func didLongPressSticker(
        _ cell: CVCell,
        itemViewModel: CVItemViewModelImpl,
        shouldAllowMessageSendActions: Bool,
    ) {}

    func didLongPressPaymentMessage(
        _ cell: CVCell,
        itemViewModel: CVItemViewModelImpl,
        shouldAllowMessageSendActions: Bool,
    ) {}

    func didLongPressPoll(
        _ cell: CVCell,
        itemViewModel: CVItemViewModelImpl,
        shouldAllowMessageSendActions: Bool,
    ) {}

    func didTapPayment(_ payment: PaymentsHistoryItem) {}

    func didChangeLongPress(_ itemViewModel: CVItemViewModelImpl) {}

    func didEndLongPress(_ itemViewModel: CVItemViewModelImpl) {}

    func didCancelLongPress(_ itemViewModel: CVItemViewModelImpl) {}

    // MARK: -

    func willBecomeVisibleWithSkippedDownloads(_ message: TSMessage) {}

    func didTapSkippedDownloads(_ message: TSMessage) {}

    func didCancelDownload(_ message: TSMessage, attachmentId: Attachment.IDType) {}

    // MARK: -

    func didTapReplyToItem(_ itemViewModel: CVItemViewModelImpl) {}

    func didTapSenderAvatar(_ interaction: TSInteraction) {}

    func shouldAllowMessageSendActionsForItem(_ itemViewModel: CVItemViewModelImpl) -> Bool { false }

    func didTapReactions(
        reactionState: InteractionReactionState,
        message: TSMessage,
    ) {}

    func didTapTruncatedTextMessage(_ itemViewModel: CVItemViewModelImpl) {}

    func didTapShowEditHistory(_ itemViewModel: CVItemViewModelImpl) {}

    var hasPendingMessageRequest: Bool { false }

    func didTapUndownloadableMedia() {}

    func didTapUndownloadableGenericFile() {}

    func didTapUndownloadableOversizeText() {}

    func didTapUndownloadableAudio() {}

    func didTapUndownloadableSticker() {}

    func didTapBrokenVideo() {}

    func didTapBodyMedia(
        itemViewModel: CVItemViewModelImpl,
        attachment: ReferencedAttachment,
        imageView: UIView,
    ) {}

    func didTapGenericAttachment(
        _ attachment: CVComponentGenericAttachment,
    ) -> CVAttachmentTapAction { .default }

    func didTapQuotedReply(_ quotedReply: QuotedReplyModel) {}

    func didTapLinkPreview(url: URL) {}

    func didTapContactShare(_ contactShare: ContactShareViewModel) {}

    func didTapSendMessage(to phoneNumbers: [String]) {}

    func didTapSendMessage(toAci aci: Aci, sharedName: OWSContactName) {}

    func didTapSendInvite(toContactShare contactShare: ContactShareViewModel) {}

    func didTapAddToContacts(contactShare: ContactShareViewModel) {}

    func didTapStickerPack(_ stickerPackInfo: StickerPackInfo) {}

    func didTapGroupInviteLink(url: PossibleGroupInviteLinkUrl) {}

    func didTapProxyLink(url: URL) {}

    func didTapShowMessageDetail(_ itemViewModel: CVItemViewModelImpl) {}

    func willWrapGift(_ messageUniqueId: String) -> Bool { false }

    func willShakeGift(_ messageUniqueId: String) -> Bool { false }

    func willUnwrapGift(_ itemViewModel: CVItemViewModelImpl) {}

    func didTapGiftBadge(
        _ itemViewModel: CVItemViewModelImpl,
        profileBadge: ProfileBadge,
        isExpired: Bool,
        isRedeemed: Bool,
    ) {}

    func prepareMessageDetailForInteractivePresentation(_ itemViewModel: CVItemViewModelImpl) {}

    func beginCellAnimation(maximumDuration: TimeInterval) -> EndCellAnimation {
        return {}
    }

    var wallpaperBlurProvider: WallpaperBlurProvider? { nil }

    var selectionState: CVSelectionState { CVSelectionState() }

    func didTapPreviouslyVerifiedIdentityChange(_ address: SignalServiceAddress) {}

    func didTapUnverifiedIdentityChange(_ address: SignalServiceAddress) {}

    func didTapSessionRefreshMessage(_ message: TSErrorMessage) {}

    func didTapResendGroupUpdateForErrorMessage(_ errorMessage: TSErrorMessage) {}

    func didTapIndividualCall(_ call: TSCall) {}

    func didTapLearnMoreMissedCallFromBlockedContact(_ call: TSCall) {}

    func didTapGroupCall() {}

    func didTapPendingOutgoingMessage(_ message: TSOutgoingMessage) {}

    func didTapFailedMessage(_ message: TSMessage) {}

    func didTapGroupMigrationLearnMore() {}

    func didTapGroupInviteLinkPromotion() {}

    func didTapViewGroupDescription(newGroupDescription: String) {}

    func didTapNameEducation(type: SafetyTipsType) {}

    func didTapShowConversationSettings() {}

    func didTapShowConversationSettingsAndShowMemberRequests() {}

    func didTapBlockRequest(
        secretParams: GroupSecretParams,
        requesterName: String,
        requesterAci: Aci,
    ) {}

    func didTapShowUpgradeAppUI() {}

    func didTapUpdateSystemContact(
        _ address: SignalServiceAddress,
        newNameComponents: PersonNameComponents,
    ) {}

    func didTapPhoneNumberChange(aci: Aci, phoneNumberOld: String, phoneNumberNew: String) {}

    func didTapViewOnceAttachment(_ interaction: TSInteraction) {}

    func didTapViewOnceExpired(_ interaction: TSInteraction) {}

    func didTapContactName(thread: TSContactThread) {}

    func didTapUnknownThreadWarningGroup() {}
    func didTapUnknownThreadWarningContact() {}
    func didTapDeliveryIssueWarning(_ message: TSErrorMessage) {}

    func didTapActivatePayments() {}
    func didTapSendPayment() {}

    func didTapThreadMergeLearnMore(phoneNumber: String) {}

    func didTapReportSpamLearnMore() {}

    func didTapMessageRequestAcceptedOptions() {}

    func didTapJoinCallLinkCall(callLink: CallLink) {}

    func didTapViewVotes(poll: OWSPoll) {}

    func didTapViewPoll(pollInteractionUniqueId: String) {}

    func didTapVoteOnPoll(poll: OWSPoll, optionIndex: UInt32, isUnvote: Bool) {}

    func didTapViewPinnedMessage(pinnedMessageUniqueId: String) {}

    func didTapSafetyTips() {}

    func didTapReleaseNotesAnnouncementAction(action: RemoteAnnouncementModel.Manifest.Action) {}
}
