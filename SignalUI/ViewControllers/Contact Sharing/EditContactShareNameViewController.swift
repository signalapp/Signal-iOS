//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

private protocol ContactNameFieldViewDelegate: AnyObject {
    func nameFieldDidChange()
}

private class ContactNameFieldView: UIView {
    weak var delegate: ContactNameFieldViewDelegate?

    let name: String

    private lazy var textField: UITextField = {
        let textField = UITextField()
        textField.font = .dynamicTypeBody
        textField.textColor = Theme.primaryTextColor
        textField.placeholder = name
        textField.autocapitalizationType = .words
        return textField
    }()

    var isEmpty: Bool { value().isEmpty }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    required init(name: String, value: String?, delegate: ContactNameFieldViewDelegate) {
        self.name = name
        self.delegate = delegate

        super.init(frame: .zero)

        isUserInteractionEnabled = true

        textField.text = value
        addSubview(textField)
        textField.autoPinEdgesToSuperviewEdges()
        textField.addTarget(self, action: #selector(textFieldDidChange), for: .editingChanged)
    }

    @objc
    private func textFieldDidChange(sender: UITextField) {
        delegate?.nameFieldDidChange()
    }

    public func value() -> String {
        return textField.text?.stripped ?? ""
    }
}

public protocol EditContactShareNameViewControllerDelegate: AnyObject {
    func editContactShareNameView(_ editContactShareNameView: EditContactShareNameViewController,
                                  didFinishWith contactName: OWSContactName)
}

// MARK: -

public class EditContactShareNameViewController: OWSTableViewController2, ContactNameFieldViewDelegate {

    private weak var editingDelegate: EditContactShareNameViewControllerDelegate?

    private let contactShare: ContactShareViewModel

    private lazy var namePrefixView = ContactNameFieldView(
        name: OWSLocalizedString("CONTACT_FIELD_NAME_PREFIX", comment: "Label for the 'name prefix' field of a contact."),
        value: contactShare.name.namePrefix,
        delegate: self
    )
    private lazy var givenNameView = ContactNameFieldView(
        name: OWSLocalizedString("CONTACT_FIELD_GIVEN_NAME", comment: "Label for the 'given name' field of a contact."),
        value: contactShare.name.givenName,
        delegate: self
    )
    private lazy var middleNameView = ContactNameFieldView(
        name: OWSLocalizedString("CONTACT_FIELD_MIDDLE_NAME", comment: "Label for the 'middle name' field of a contact."),
        value: contactShare.name.middleName,
        delegate: self
    )
    private lazy var familyNameView = ContactNameFieldView(
        name: OWSLocalizedString("CONTACT_FIELD_FAMILY_NAME", comment: "Label for the 'family name' field of a contact."),
        value: contactShare.name.familyName,
        delegate: self
    )
    private lazy var nameSuffixView = ContactNameFieldView(
        name: OWSLocalizedString("CONTACT_FIELD_NAME_SUFFIX", comment: "Label for the 'name suffix' field of a contact."),
        value: contactShare.name.nameSuffix,
        delegate: self
    )
    private lazy var organizationNameView = ContactNameFieldView(
        name: OWSLocalizedString("CONTACT_FIELD_ORGANIZATION", comment: "Label for the 'organization' field of a contact."),
        value: contactShare.name.organizationName,
        delegate: self
    )

    private func allNameFieldViews() -> [ContactNameFieldView] {
        return [
            namePrefixView,
            givenNameView,
            middleNameView,
            familyNameView,
            nameSuffixView,
            organizationNameView
        ]
    }

    // MARK: Initializers

    required public init(contactShare: ContactShareViewModel, delegate: EditContactShareNameViewControllerDelegate) {
        self.contactShare = contactShare
        self.editingDelegate = delegate

        super.init()
    }

    // MARK: - View Lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.title = OWSLocalizedString("CONTACT_SHARE_EDIT_NAME_VIEW_TITLE",
                                                  comment: "Title for the 'edit contact share name' view.")
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(didPressCancel))
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(didPressDone))

        updateContents()
        updateNavigationBar()
    }

    private func updateNavigationBar() {
        navigationItem.rightBarButtonItem?.isEnabled = canSaveChanges()
    }

    // MARK: -

    private func updateContents() {
        let tableItems: [OWSTableItem] = allNameFieldViews().map { nameFieldView in
            return OWSTableItem(customCellBlock: {
                let cell = OWSTableItem.newCell()
                cell.contentView.addSubview(nameFieldView)
                nameFieldView.autoPinHeightToSuperview(withMargin: 10)
                nameFieldView.autoPinWidthToSuperviewMargins()
                return cell
            })
        }
        contents = OWSTableContents(sections: [OWSTableSection(items: tableItems)])
    }

    private func canSaveChanges() -> Bool {
        for fieldView in allNameFieldViews() {
            if !fieldView.isEmpty {
                return true
            }
        }
        return false
    }

    @objc
    private func didPressDone() {
        guard let editingDelegate else {
            owsFailDebug("missing delegate.")
            return
        }

        let newName = OWSContactName(
            givenName: givenNameView.value(),
            familyName: familyNameView.value(),
            namePrefix: namePrefixView.value(),
            nameSuffix: nameSuffixView.value(),
            middleName: middleNameView.value(),
            organizationName: organizationNameView.value()
        )
        editingDelegate.editContactShareNameView(self, didFinishWith: newName)

        navigationController?.popViewController(animated: true)
    }

    @objc
    private func didPressCancel() {
        navigationController?.popViewController(animated: true)
    }

    // MARK: - ContactNameFieldViewDelegate

    fileprivate func nameFieldDidChange() {
        updateNavigationBar()
    }
}
