//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import SignalServiceKit

public protocol ContactShareViewControllerDelegate: AnyObject {

    func contactShareViewController(
        _ viewController: ContactShareViewController,
        didApproveContactShare contactShare: ContactShareDraft,
    )

    func titleForContactShareViewController(_ viewController: ContactShareViewController) -> String?

    func recipientsDescriptionForContactShareViewController(_ viewController: ContactShareViewController) -> String?

    func approvalModeForContactShareViewController(_ viewController: ContactShareViewController) -> ApprovalMode
}

public class ContactShareViewController: OWSTableViewController2, ApprovalFooterDelegate,
    EditContactShareNameViewControllerDelegate
{

    public weak var shareDelegate: ContactShareViewControllerDelegate?

    private var approvalMode: ApprovalMode {
        shareDelegate?.approvalModeForContactShareViewController(self) ?? .send
    }

    // MARK: Contact data

    private var contactShareDraft: ContactShareDraft

    private lazy var avatarField = ContactShareAvatarField(contactShareDraft: contactShareDraft)

    private lazy var nicknameField: ContactShareField? = {
        guard let nickname = contactShareDraft.signalNickname else { return nil }
        return ContactShareNicknameField(OWSContactNickname(nickname: nickname), includedByDefault: false)
    }()

    private lazy var noteField: ContactShareField? = {
        guard let note = contactShareDraft.signalNote?.strippedOrNil else { return nil }
        return ContactShareNoteField(OWSContactNote(note: note), includedByDefault: false)
    }()

    private lazy var contactShareFields: [ContactShareField] = {
        var fields = [ContactShareField]()

        fields += contactShareDraft.phoneNumbers.map { ContactSharePhoneNumber($0) }
        fields += contactShareDraft.emails.map { ContactShareEmail($0, includedByDefault: false) }
        fields += contactShareDraft.addresses.map { ContactShareAddress($0, includedByDefault: false) }

        return fields
    }()

    private func filteredContactShare() -> ContactShareDraft {
        let result = contactShareDraft.newContact(withName: contactShareDraft.name)

        // The avatar row is always "included". User can select initials to send no data.
        if let avatarField {
            avatarField.applyToContact(contact: result)
        }

        for field in contactShareFields {
            if field.isIncluded {
                field.applyToContact(contact: result)
            }
        }

        if let nicknameField, nicknameField.isIncluded {
            nicknameField.applyToContact(contact: result)
        }

        if let noteField, noteField.isIncluded {
            noteField.applyToContact(contact: result)
        }

        return result
    }

    // MARK: UIViewController

    public init(contactShareDraft: ContactShareDraft) {
        self.contactShareDraft = contactShareDraft

        super.init()
    }

    override public func viewDidLoad() {
        super.viewDidLoad()

        if let title = shareDelegate?.titleForContactShareViewController(self) {
            navigationItem.title = title
        } else {
            navigationItem.title = OWSLocalizedString(
                "CONTACT_SHARE_APPROVAL_VIEW_TITLE",
                comment: "Title for the 'Approve contact share' view.",
            )
        }
        if let recipientsDescription = shareDelegate?.recipientsDescriptionForContactShareViewController(self) {
            footerView.setNamesText(recipientsDescription, animated: false)
        }
        footerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(footerView)
        NSLayoutConstraint.activate([
            footerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            footerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            footerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        if #available(iOS 26, *) {
            let interaction = UIScrollEdgeElementContainerInteraction()
            interaction.edge = .bottom
            interaction.scrollView = tableView
            footerView.addInteraction(interaction)
        }

        updateContent()
    }

    override public func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        let footerHeight = footerView.frame.height - footerView.safeAreaInsets.bottom
        tableView.contentInset.bottom = footerHeight
        tableView.verticalScrollIndicatorInsets.bottom = footerHeight
    }

    override public func contentSizeCategoryDidChange() {
        super.contentSizeCategoryDidChange()
        updateContent()
    }

    // MARK: UI

    private lazy var footerView: ApprovalFooterView = {
        let footerView = ApprovalFooterView()
        footerView.delegate = self
        return footerView
    }()

    private func updateContent() {
        var tableItems = [OWSTableItem]()

        // Avatar
        if let avatarField {
            tableItems.append(OWSTableItem(
                customCellBlock: { [weak self] in
                    let avatarImage = avatarField.selectedOption?.image ?? self?.initialsAvatarImage(diameter: 56)
                    return ContactShareFieldCell.avatarCell(
                        avatarImage: avatarImage,
                        selectedSource: avatarField.selectedSource,
                    )
                },
                actionBlock: { [weak self] in
                    self?.showAvatarPicker(avatarField: avatarField)
                },
            ))
        }

        // Name
        tableItems.append(OWSTableItem(
            customCellBlock: { [weak self] in
                guard let contactName = self?.contactShareDraft.displayName else {
                    return OWSTableItem.newCell()
                }
                return ContactShareFieldCell.contactNameCell(for: contactName)
            },
            actionBlock: { [weak self] in
                self?.openContactNameEditingView()
            },
        ))

        // Other fields
        tableItems += contactShareFields.map { field in
            OWSTableItem(
                customCellBlock: {
                    return ContactShareFieldCell(field: field)
                },
                actionBlock: { [weak self] in
                    self?.toggleSelection(for: field)
                },
            )
        }

        // Nickname
        if let nicknameField {
            tableItems.append(OWSTableItem(
                customCellBlock: {
                    return ContactShareFieldCell(field: nicknameField)
                },
                actionBlock: { [weak self] in
                    self?.toggleSelection(for: nicknameField)
                },
            ))
        }

        // Note
        if let noteField {
            tableItems.append(OWSTableItem(
                customCellBlock: {
                    return ContactShareFieldCell(field: noteField)
                },
                actionBlock: { [weak self] in
                    self?.toggleSelection(for: noteField)
                },
            ))
        }

        let section = OWSTableSection(items: tableItems)
        if contactShareDraft.aci != nil {
            let format = OWSLocalizedString(
                "CONTACT_SHARE_SIGNAL_ACCOUNT_NOTICE_FORMAT",
                comment: "Notice at the top of the 'Share Contact' view when the shared contact includes their Signal account. Embeds {{ contact name }}.",
            )
            var configuration = UIListContentConfiguration.groupedHeader()
            configuration.text = String(format: format, contactShareDraft.displayName)
            configuration.textProperties.font = Self.defaultFooterFont
            configuration.textProperties.color = Self.defaultFooterTextColor
            configuration.textProperties.transform = .none
            configuration.directionalLayoutMargins.top = 16
            let headerView = UITableViewHeaderFooterView()
            headerView.contentConfiguration = configuration
            section.customHeaderView = headerView
        }

        contents = OWSTableContents(sections: [section])
    }

    private func toggleSelection(for contactShareField: ContactShareField) {
        contactShareField.isIncluded = !contactShareField.isIncluded

        guard
            let cell = tableView.visibleCells.first(where: { visibleCell in
                guard let contactFieldCell = visibleCell as? ContactShareFieldCell else { return false }
                return contactFieldCell.field === contactShareField
            }) as? ContactShareFieldCell else { return }

        cell.updateCheckmarkState()
    }

    // MARK: -

    private func didPressSendButton() {
        guard contactShareDraft.ows_isValid else {
            OWSActionSheets.showErrorAlert(message: OWSLocalizedString(
                "CONTACT_SHARE_INVALID_CONTACT",
                comment: "Error indicating that an invalid contact cannot be shared.",
            ))
            return
        }

        guard let shareDelegate else {
            owsFailDebug("missing delegate.")
            return
        }

        let filteredContactShare = filteredContactShare()
        owsPrecondition(filteredContactShare.ows_isValid)
        shareDelegate.contactShareViewController(self, didApproveContactShare: filteredContactShare)
    }

    private func initialsAvatarImage(diameter: UInt) -> UIImage? {
        SSKEnvironment.shared.databaseStorageRef.read { tx in
            SSKEnvironment.shared.avatarBuilderRef.defaultAvatarImage(
                personNameComponents: contactShareDraft.name.components,
                diameterPoints: diameter,
                transaction: tx,
            )
        }
    }

    private func showAvatarPicker(avatarField: ContactShareAvatarField) {
        let sheet = ContactShareAvatarPickerSheet(
            options: avatarField.options,
            initialsImage: initialsAvatarImage(diameter: 96),
            selectedSource: avatarField.selectedSource,
        ) { [weak self] selectedSource in
            avatarField.selectedSource = selectedSource
            self?.tableView.reloadData()
        }
        present(sheet, animated: true)
    }

    private func openContactNameEditingView() {
        let view = EditContactShareNameViewController(contactShareDraft: contactShareDraft, delegate: self)
        present(OWSNavigationController(rootViewController: view), animated: true)
    }

    private class ContactShareFieldCell: UITableViewCell {

        let field: ContactShareField

        private lazy var checkmark = SelectionIndicatorView()

        init(field: ContactShareField) {
            self.field = field

            let fieldContentView: UIView? = {
                switch field {
                case let phoneNumberField as ContactSharePhoneNumber:
                    return ContactFieldViewHelper.contactFieldView(forPhoneNumber: phoneNumberField.value)

                case let emailField as ContactShareEmail:
                    return ContactFieldViewHelper.contactFieldView(forEmail: emailField.value)

                case let addressField as ContactShareAddress:
                    return ContactFieldViewHelper.contactFieldView(forAddress: addressField.value)

                case let nicknameField as ContactShareNicknameField:
                    return ContactFieldViewHelper.contactFieldView(forNickname: nicknameField.value.nickname)

                case let noteField as ContactShareNoteField:
                    return ContactFieldViewHelper.contactFieldView(forNote: noteField.value.note)

                default:
                    owsFailDebug("Invalid field")
                    return nil
                }
            }()

            super.init(style: .default, reuseIdentifier: nil)

            selectionStyle = .none

            let stackView = UIStackView(arrangedSubviews: [checkmark])
            if let fieldContentView {
                stackView.addArrangedSubview(fieldContentView)
            }
            stackView.axis = .horizontal
            stackView.spacing = 12
            stackView.alignment = .center
            contentView.addSubview(stackView)
            stackView.autoPinHeightToSuperview(withMargin: 10)
            stackView.autoPinWidthToSuperviewMargins()

            updateCheckmarkState()
        }

        class func contactNameCell(for contactName: String) -> UITableViewCell {
            let checkmark = SelectionIndicatorView()
            checkmark.isSelected = true

            let nameField = ContactFieldViewHelper.contactFieldView(forContactName: contactName)

            return disclosureCell(checkmark: checkmark, fieldView: nameField, verticalMargin: 14)
        }

        class func avatarCell(
            avatarImage: UIImage?,
            selectedSource: ContactShareAvatarOption.Source?,
        ) -> UITableViewCell {
            let checkmark = SelectionIndicatorView()
            checkmark.isSelected = true

            let avatarView = avatarImage.map { ContactFieldViewHelper.contactFieldView(forAvatarImage: $0) }

            let cell = disclosureCell(checkmark: checkmark, fieldView: avatarView, verticalMargin: 10)
            cell.isAccessibilityElement = true
            cell.accessibilityLabel = OWSLocalizedString(
                "CONTACT_SHARE_AVATAR_ROW_LABEL",
                comment: "Accessibility label for the row that chooses which photo to include when sharing a contact.",
            )
            cell.accessibilityValue = ContactShareAvatarOption.localizedVoiceOverName(source: selectedSource)
            cell.accessibilityTraits = .button
            return cell
        }

        private class func disclosureCell(
            checkmark: SelectionIndicatorView,
            fieldView: UIView?,
            verticalMargin: CGFloat,
        ) -> UITableViewCell {
            let stackView = UIStackView(arrangedSubviews: [checkmark])
            if let fieldView {
                stackView.addArrangedSubview(fieldView)
            }
            stackView.axis = .horizontal
            stackView.spacing = 12
            stackView.alignment = .center

            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.accessoryType = .disclosureIndicator
            cell.contentView.addSubview(stackView)
            stackView.autoPinHeightToSuperview(withMargin: verticalMargin)
            stackView.autoPinWidthToSuperviewMargins()

            return cell
        }

        required init(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func updateCheckmarkState() {
            checkmark.isSelected = field.isIncluded
        }
    }

    // MARK: - EditContactShareNameViewControllerDelegate

    public func editContactShareNameView(
        _ editContactShareNameView: EditContactShareNameViewController,
        didFinishWith contactName: OWSContactName,
    ) {
        contactShareDraft.name = contactName
        updateContent()
    }

    // MARK: - ApprovalFooterDelegate

    public func approvalFooterDelegateDidRequestProceed(_ approvalFooterView: ApprovalFooterView) {
        didPressSendButton()
    }

    public func approvalMode(_ approvalFooterView: ApprovalFooterView) -> ApprovalMode { approvalMode }

    public func approvalFooterDidBeginEditingText() {}
}
