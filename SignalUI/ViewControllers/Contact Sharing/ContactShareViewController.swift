//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

public protocol ContactShareViewControllerDelegate: AnyObject {

    func contactShareViewController(_ viewController: ContactShareViewController,
                                    didApproveContactShare contactShare: ContactShareViewModel)

    func contactShareViewControllerDidCancel(_ viewController: ContactShareViewController)

    func titleForContactShareViewController(_ viewController: ContactShareViewController) -> String?

    func recipientsDescriptionForContactShareViewController(_ viewController: ContactShareViewController) -> String?

    func approvalModeForContactShareViewController(_ viewController: ContactShareViewController) -> ApprovalMode
}

public class ContactShareViewController: OWSTableViewController2 {

    public weak var shareDelegate: ContactShareViewControllerDelegate?

    private var approvalMode: ApprovalMode {
        return shareDelegate?.approvalModeForContactShareViewController(self) ?? .send
    }

    // MARK: Contact data

    private var contactShare: ContactShareViewModel

    private lazy var avatarField: ContactShareField? = {
        guard let avatarData = contactShare.avatarImageData else { return nil }
        guard let avatarImage = contactShare.avatarImage else {
            owsFailDebug("could not load avatar image.")
            return nil
        }
        return ContactShareAvatarField(OWSContactAvatar(avatarImage: avatarImage, avatarData: avatarData))
    }()

    private lazy var contactShareFields: [ContactShareField] = {
        var fields = [ContactShareField]()

        fields += contactShare.phoneNumbers.map { ContactSharePhoneNumber($0) }
        fields += contactShare.emails.map { ContactShareEmail($0) }
        fields += contactShare.addresses.map { ContactShareAddress($0) }

        return fields
    }()

    private func filteredContactShare() -> ContactShareViewModel {
        let result = contactShare.newContact(withName: contactShare.name)

        if let avatarField, avatarField.isIncluded {
            avatarField.applyToContact(contact: result)
        }

        for field in contactShareFields {
            if field.isIncluded {
                field.applyToContact(contact: result)
            }
        }

        return result
    }

    // MARK: UIViewController

    required public init(contactShare: ContactShareViewModel) {
        self.contactShare = contactShare

        super.init()
    }

    override public func viewDidLoad() {
        super.viewDidLoad()

        if let title = shareDelegate?.titleForContactShareViewController(self) {
            navigationItem.title = title
        } else {
            navigationItem.title = OWSLocalizedString("CONTACT_SHARE_APPROVAL_VIEW_TITLE",
                                                      comment: "Title for the 'Approve contact share' view.")
        }

        updateContent()
        updateControls()
    }

    override public func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        updateControls()
    }

    public override var canBecomeFirstResponder: Bool {
        return true
    }

    public override var inputAccessoryView: UIView? {
        return currentInputAcccessoryView
    }

    // MARK: UI

    private var currentInputAcccessoryView: UIView? {
        didSet {
            if oldValue != currentInputAcccessoryView {
                reloadInputViews()
            }
        }
    }

    private lazy var footerView: ApprovalFooterView = {
        let footerView = ApprovalFooterView()
        footerView.delegate = self
        return footerView
    }()

    private func isAtLeastOneFieldSelected() -> Bool {
        for field in contactShareFields {
            if field.isIncluded {
                return true
            }
        }
        return false
    }

    private func updateControls() {
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(didPressCancel))

        guard isAtLeastOneFieldSelected() else {
            currentInputAcccessoryView = nil
            return
        }

        guard let recipientsDescription = shareDelegate?.recipientsDescriptionForContactShareViewController(self) else {
            currentInputAcccessoryView = nil
            return
        }
        footerView.setNamesText(recipientsDescription, animated: false)
        currentInputAcccessoryView = footerView
    }

    private func updateContent() {
        var tableItems = [OWSTableItem]()

        // Name
        tableItems.append(OWSTableItem(
            customCellBlock: { [weak self] in
                guard let contactName = self?.contactShare.displayName else {
                    return OWSTableItem.newCell()
                }
                return ContactShareFieldCell.contactNameCell(for: contactName)
            },
            actionBlock: { [weak self] in
                self?.openContactNameEditingView()
            }
        ))

       // Avatar
        if let avatarField {
            tableItems.append(OWSTableItem(
                customCellBlock: {
                    return ContactShareFieldCell(field: avatarField)
                },
                actionBlock: { [weak self] in
                    self?.toggleSelection(for: avatarField)
                }
            ))
        }

        // Other fields
        tableItems += contactShareFields.map { field in
            return OWSTableItem(
                customCellBlock: {
                    return ContactShareFieldCell(field: field)
                },
                actionBlock: { [weak self] in
                    self?.toggleSelection(for: field)
                })
        }
        contents = OWSTableContents(sections: [OWSTableSection(items: tableItems)])
    }

    private func toggleSelection(for contactShareField: ContactShareField) {
        contactShareField.isIncluded = !contactShareField.isIncluded

        guard let cell = tableView.visibleCells.first(where: { visibleCell in
            guard let contactFieldCell = visibleCell as? ContactShareFieldCell else { return false }
            return contactFieldCell.field === contactShareField
        }) as? ContactShareFieldCell else { return }

        cell.updateCheckmarkState()
    }

    // MARK: -

    @objc
    private func didPressSendButton() {
        AssertIsOnMainThread()

        guard isAtLeastOneFieldSelected() else {
            OWSActionSheets.showErrorAlert(message: OWSLocalizedString("CONTACT_SHARE_NO_FIELDS_SELECTED",
                                                                       comment: "Error indicating that at least one contact field must be selected before sharing a contact."))
            return
        }
        guard contactShare.ows_isValid else {
            OWSActionSheets.showErrorAlert(message: OWSLocalizedString("CONTACT_SHARE_INVALID_CONTACT",
                                                                       comment: "Error indicating that an invalid contact cannot be shared."))
            return
        }

        guard let shareDelegate else {
            owsFailDebug("missing delegate.")
            return
        }

        let filteredContactShare = filteredContactShare()
        owsAssert(filteredContactShare.ows_isValid)
        shareDelegate.contactShareViewController(self, didApproveContactShare: filteredContactShare)
    }

    @objc
    private func didPressCancel() {
        guard let shareDelegate else {
            owsFailDebug("missing delegate.")
            return
        }

        shareDelegate.contactShareViewControllerDidCancel(self)
    }

    private func openContactNameEditingView() {
        let view = EditContactShareNameViewController(contactShare: contactShare, delegate: self)
        navigationController?.pushViewController(view, animated: true)
    }

    private class ContactShareFieldCell: UITableViewCell {

        let field: ContactShareField

        private lazy var checkmark: UIImageView = {
            let checkmark = UIImageView(
                image: Theme.iconImage(.circle).withTintColor(.ows_gray25, renderingMode: .automatic),
                highlightedImage: Theme.iconImage(.checkCircleFill).withTintColor(Theme.accentBlueColor, renderingMode: .automatic)
            )
            checkmark.autoSetDimensions(to: .square(24))
            return checkmark
        }()

        init(field: ContactShareField) {
            self.field = field

            let fieldContentView: UIView? = {
                switch field {
                case let avatarField as ContactShareAvatarField:
                    return ContactFieldViewHelper.contactFieldView(forAvatarImage: avatarField.value.avatarImage)

                case let phoneNumberField as ContactSharePhoneNumber:
                    return ContactFieldViewHelper.contactFieldView(forPhoneNumber: phoneNumberField.value)

                case let emailField as ContactShareEmail:
                    return ContactFieldViewHelper.contactFieldView(forEmail: emailField.value)

                case let addressField as ContactShareAddress:
                    return ContactFieldViewHelper.contactFieldView(forAddress: addressField.value)

                default:
                    owsFailDebug("Invalid field")
                    return nil
                }
            }()

            super.init(style: .default, reuseIdentifier: nil)

            selectionStyle = .none

            let stackView = UIStackView(arrangedSubviews: [ checkmark ])
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
            let checkmark = UIImageView(image: Theme.iconImage(.checkCircleFill).withTintColor(.ows_gray25, renderingMode: .automatic))
            let nameField = ContactFieldViewHelper.contactFieldView(forContactName: contactName)

            let stackView = UIStackView(arrangedSubviews: [ checkmark, nameField ])
            stackView.axis = .horizontal
            stackView.spacing = 12
            stackView.alignment = .center

            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.accessoryType = .disclosureIndicator
            cell.contentView.addSubview(stackView)
            stackView.autoPinHeightToSuperview(withMargin: 14)
            stackView.autoPinWidthToSuperviewMargins()

            return cell
       }

        required init(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func updateCheckmarkState() {
            checkmark.isHighlighted = field.isIncluded
        }
    }
}

extension ContactShareViewController: EditContactShareNameViewControllerDelegate {

    public func editContactShareNameView(_ editContactShareNameView: EditContactShareNameViewController,
                                         didFinishWith contactName: OWSContactName) {
        contactShare = contactShare.copy(withName: contactName)
        tableView.reloadData()
        updateControls()
    }
}

// MARK: -

extension ContactShareViewController: ApprovalFooterDelegate {

    public func approvalFooterDelegateDidRequestProceed(_ approvalFooterView: ApprovalFooterView) {
        didPressSendButton()
    }

    public func approvalMode(_ approvalFooterView: ApprovalFooterView) -> ApprovalMode {
        return approvalMode
    }

    public func approvalFooterDidBeginEditingText() {}
}
