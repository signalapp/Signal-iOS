//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit

@objc
public protocol ApproveContactShareViewControllerDelegate: class {
    func approveContactShare(_ approveContactShare: ApproveContactShareViewController, didApproveContactShare contactShare: OWSContact)
    func approveContactShare(_ approveContactShare: ApproveContactShareViewController, didCancelContactShare contactShare: OWSContact)
}

// MARK: -

class ContactShareField: NSObject {

    private var isIncludedFlag = true

    func localizedLabel() -> String {
        preconditionFailure("This method must be overridden")
    }

    func isIncluded() -> Bool {
        return isIncludedFlag
    }

    func setIsIncluded(_ isIncluded: Bool) {
        isIncludedFlag = isIncluded
    }

    func applyToContact(contact: OWSContact) {
        preconditionFailure("This method must be overridden")
    }
}

// MARK: -

class ContactSharePhoneNumber: ContactShareField {

    let value: OWSContactPhoneNumber

    required init(_ value: OWSContactPhoneNumber) {
        self.value = value

        super.init()
    }

    override func localizedLabel() -> String {
        return value.localizedLabel()
    }

    override func applyToContact(contact: OWSContact) {
        assert(isIncluded())

        var values = [OWSContactPhoneNumber]()
        values += contact.phoneNumbers
        values.append(value)
        contact.phoneNumbers = values
    }
}

// MARK: -

class ContactShareEmail: ContactShareField {

    let value: OWSContactEmail

    required init(_ value: OWSContactEmail) {
        self.value = value

        super.init()
    }

    override func localizedLabel() -> String {
        return value.localizedLabel()
    }

    override func applyToContact(contact: OWSContact) {
        assert(isIncluded())

        var values = [OWSContactEmail]()
        values += contact.emails
        values.append(value)
        contact.emails = values
    }
}

// MARK: -

class ContactShareAddress: ContactShareField {

    let value: OWSContactAddress

    required init(_ value: OWSContactAddress) {
        self.value = value

        super.init()
    }

    override func localizedLabel() -> String {
        return value.localizedLabel()
    }

    override func applyToContact(contact: OWSContact) {
        assert(isIncluded())

        var values = [OWSContactAddress]()
        values += contact.addresses
        values.append(value)
        contact.addresses = values
    }
}

// MARK: -

class ContactShareFieldView: UIView {

    let field: ContactShareField

    let previewViewBlock : (() -> UIView)

    private var checkbox: UIButton!

    // MARK: - Initializers

    @available(*, unavailable, message: "use init(call:) constructor instead.")
    required init?(coder aDecoder: NSCoder) {
        fatalError("Unimplemented")
    }

    required init(field: ContactShareField, previewViewBlock : @escaping (() -> UIView)) {
        self.field = field
        self.previewViewBlock = previewViewBlock

        super.init(frame: CGRect.zero)

        self.isUserInteractionEnabled = true
        self.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(wasTapped)))

        createContents()
    }

    let hSpacing = CGFloat(10)
    let hMargin = CGFloat(0)

    func createContents() {
        self.layoutMargins.left = 0
        self.layoutMargins.right = 0

        let checkbox = UIButton(type: .custom)
        self.checkbox = checkbox
        // TODO: Use real assets.
        checkbox.setTitle("☐", for: .normal)
        checkbox.setTitle("☒", for: .selected)
        checkbox.setTitleColor(UIColor.black, for: .normal)
        checkbox.setTitleColor(UIColor.black, for: .selected)
        checkbox.titleLabel?.font = UIFont.ows_dynamicTypeBody
        checkbox.isSelected = field.isIncluded()
        // Disable the checkbox; the entire row is hot.
        checkbox.isUserInteractionEnabled = false
        addSubview(checkbox)
        checkbox.autoPinEdge(toSuperviewEdge: .leading, withInset: hMargin)
        checkbox.autoVCenterInSuperview()
        checkbox.setCompressionResistanceHigh()
        checkbox.setContentHuggingHigh()

        let nameLabel = UILabel()
        nameLabel.text = field.localizedLabel()
        nameLabel.font = UIFont.ows_dynamicTypeCaption1
        nameLabel.textColor = UIColor.black
        nameLabel.lineBreakMode = .byTruncatingTail
        addSubview(nameLabel)
        nameLabel.autoPinTopToSuperviewMargin()
        nameLabel.autoPinLeading(toTrailingEdgeOf: checkbox, offset: hSpacing)
        nameLabel.autoPinTrailingToSuperviewMargin(withInset: hMargin)

        let previewView = previewViewBlock()
        addSubview(previewView)
        previewView.autoPinEdge(.top, to: .bottom, of: nameLabel, withOffset: 3)
        previewView.autoPinBottomToSuperviewMargin()
        previewView.autoPinLeading(toTrailingEdgeOf: checkbox, offset: hSpacing)
        previewView.autoPinTrailingToSuperviewMargin(withInset: hMargin)
    }

    func wasTapped(sender: UIGestureRecognizer) {
        Logger.info("\(self.logTag) \(#function)")

        guard sender.state == .recognized else {
            return
        }
        field.setIsIncluded(!field.isIncluded())
        checkbox.isSelected = field.isIncluded()
    }
}

// MARK: -

@objc
public class ApproveContactShareViewController: OWSViewController, EditContactShareNameViewControllerDelegate {
    weak var delegate: ApproveContactShareViewControllerDelegate?

    let contactsManager: OWSContactsManager

    var contactShare: OWSContact

    var fieldViews = [ContactShareFieldView]()

    var nameLabel: UILabel!

    // MARK: Initializers

    @available(*, unavailable, message:"use other constructor instead.")
    required public init?(coder aDecoder: NSCoder) {
        fatalError("unimplemented")
    }

    @objc
    required public init(contactShare: OWSContact, contactsManager: OWSContactsManager, delegate: ApproveContactShareViewControllerDelegate) {
        self.contactsManager = contactsManager
        self.contactShare = contactShare
        self.delegate = delegate

        super.init(nibName: nil, bundle: nil)

        buildFields()
    }

    func buildFields() {
        var fieldViews = [ContactShareFieldView]()

        // TODO: Avatar

        for phoneNumber in contactShare.phoneNumbers {
            let field = ContactSharePhoneNumber(phoneNumber)
            let fieldView = ContactShareFieldView(field: field, previewViewBlock: { [weak self] _ in
                guard let strongSelf = self else { return UIView() }
                return strongSelf.previewView(forPhoneNumber: phoneNumber)
            })
            fieldViews.append(fieldView)
        }
        for email in contactShare.emails {
            let field = ContactShareEmail(email)
            let fieldView = ContactShareFieldView(field: field, previewViewBlock: { [weak self] _ in
                guard let strongSelf = self else { return UIView() }
                return strongSelf.previewView(forEmail: email)
            })
            fieldViews.append(fieldView)
        }
        for address in contactShare.addresses {
            let field = ContactShareAddress(address)
            let fieldView = ContactShareFieldView(field: field, previewViewBlock: { [weak self] _ in
                guard let strongSelf = self else { return UIView() }
                return strongSelf.previewView(forAddress: address)
            })
            fieldViews.append(fieldView)
        }

        self.fieldViews = fieldViews
    }

    override public var canBecomeFirstResponder: Bool {
        return true
    }

    // MARK: - View Lifecycle

    override public func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        updateNavigationBar()
    }

    override public func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }

    override public func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
    }

    override public func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
    }

    override public func loadView() {
        super.loadView()

        self.navigationItem.title = NSLocalizedString("CONTACT_SHARE_APPROVAL_VIEW_TITLE",
                                                      comment: "Title for the 'Approve contact share' view.")

        self.view.preservesSuperviewLayoutMargins = false
        self.view.backgroundColor = UIColor.white

        updateContent()

        updateNavigationBar()
    }

    // TODO: Surface error with resolution to user if not.
    func canShareContact() -> Bool {
        return contactShare.ows_isValid()
    }

    func updateNavigationBar() {
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel,
                                                                target: self,
                                                                action: #selector(didPressCancel))

        if canShareContact() {
            self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: NSLocalizedString("ATTACHMENT_APPROVAL_SEND_BUTTON",
                                                                                              comment: "Label for 'send' button in the 'attachment approval' dialog."),
                                                                     style: .plain, target: self, action: #selector(didPressSendButton))
        } else {
            self.navigationItem.rightBarButtonItem = nil
        }

    }

    private func updateContent() {
        SwiftAssertIsOnMainThread(#function)

        guard let rootView = self.view else {
            owsFail("\(logTag) missing root view.")
            return
        }

        for subview in rootView.subviews {
            subview.removeFromSuperview()
        }

        let scrollView = UIScrollView()
        scrollView.preservesSuperviewLayoutMargins = false
        self.view.addSubview(scrollView)
        scrollView.layoutMargins = .zero
        scrollView.autoPinWidthToSuperview()
        scrollView.autoPin(toTopLayoutGuideOf: self, withInset: 0)
        scrollView.autoPinEdge(toSuperviewEdge: .bottom)

        let fieldsView = createFieldsView()

        scrollView.addSubview(fieldsView)
        fieldsView.autoPinLeadingToSuperviewMargin()
        fieldsView.autoPinTrailingToSuperviewMargin()
        fieldsView.autoPinEdge(toSuperviewEdge: .top)
        fieldsView.autoPinEdge(toSuperviewEdge: .bottom)
    }

    private func createFieldsView() -> UIView {
        SwiftAssertIsOnMainThread(#function)

        let fieldsView = UIView.container()
        fieldsView.layoutMargins = .zero
        fieldsView.preservesSuperviewLayoutMargins = false

        var lastRow: UIView?

        let addSpacerRow = {
            guard let prevRow = lastRow else {
                owsFail("\(self.logTag) missing last row")
                return
            }
            let row = UIView()
            row.backgroundColor = UIColor(rgbHex: 0xdedee1)
            fieldsView.addSubview(row)
            row.autoSetDimension(.height, toSize: 1)
            row.autoPinLeadingToSuperviewMargin(withInset: self.hMargin)
            row.autoPinTrailingToSuperviewMargin()
            row.autoPinEdge(.top, to: .bottom, of: prevRow, withOffset: 0)
            lastRow = row
        }

        let addRow: ((UIView) -> Void) = { (row) in
            if lastRow != nil {
                addSpacerRow()
            }
            fieldsView.addSubview(row)
            row.autoPinLeadingToSuperviewMargin(withInset: self.hMargin)
            row.autoPinTrailingToSuperviewMargin(withInset: self.hMargin)
            if let lastRow = lastRow {
                row.autoPinEdge(.top, to: .bottom, of: lastRow, withOffset: 0)
            } else {
                row.autoPinEdge(toSuperviewEdge: .top, withInset: 0)
            }
            lastRow = row
        }

        addRow(createNameRow())

        for fieldView in fieldViews {
            addRow(fieldView)
        }

        lastRow?.autoPinEdge(toSuperviewEdge: .bottom, withInset: 0)

        return fieldsView
    }

    private let hMargin = CGFloat(16)

    func createNameRow() -> UIView {
        let nameVMargin = CGFloat(16)

        let row = UIView()
        row.layoutMargins = UIEdgeInsets(top: nameVMargin, left: 0, bottom: nameVMargin, right: 0)

        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.layoutMargins = .zero
        stackView.spacing = 10
        row.addSubview(stackView)
        stackView.autoPinLeadingToSuperviewMargin()
        stackView.autoPinTrailingToSuperviewMargin()
        stackView.autoPinTopToSuperviewMargin()
        stackView.autoPinBottomToSuperviewMargin()

        let nameLabel = UILabel()
        self.nameLabel = nameLabel
        nameLabel.text = contactShare.displayName
        nameLabel.font = UIFont.ows_dynamicTypeBody
        nameLabel.textColor = UIColor.ows_materialBlue
        nameLabel.lineBreakMode = .byTruncatingTail
        stackView.addArrangedSubview(nameLabel)
        nameLabel.setContentHuggingHigh()

        let editNameLabel = UILabel()
        editNameLabel.text = NSLocalizedString("CONTACT_EDIT_NAME_BUTTON", comment: "Label for the 'edit name' button in the contact share approval view.")
        editNameLabel.font = UIFont.ows_dynamicTypeCaption1
        editNameLabel.textColor = UIColor.black
        stackView.addArrangedSubview(editNameLabel)
        editNameLabel.setContentHuggingHigh()
        editNameLabel.setCompressionResistanceHigh()

        // Icon
        let iconName = (self.view.isRTL() ? "system_disclosure_indicator_rtl" : "system_disclosure_indicator")
        guard let iconImage = UIImage(named: iconName) else {
            owsFail("\(logTag) missing icon.")
            return row
        }
        let iconView = UIImageView(image: iconImage.withRenderingMode(.alwaysTemplate))
        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = UIColor.black.withAlphaComponent(0.6)
        stackView.addArrangedSubview(iconView)
        iconView.setContentHuggingHigh()
        iconView.setCompressionResistanceHigh()

        row.isUserInteractionEnabled = true
        row.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didPressEditName)))

        return row
    }

    func previewView(forPhoneNumber phoneNumber: OWSContactPhoneNumber) -> UIView {
        let label = UILabel()
        label.text = PhoneNumber.bestEffortLocalizedPhoneNumber(withE164: phoneNumber.phoneNumber)
        label.font = UIFont.ows_dynamicTypeCaption1
        label.textColor = UIColor.ows_materialBlue
        label.lineBreakMode = .byTruncatingTail
        return label
    }

    func previewView(forEmail email: OWSContactEmail) -> UIView {
        let label = UILabel()
        label.text = email.email
        label.font = UIFont.ows_dynamicTypeCaption1
        label.textColor = UIColor.ows_materialBlue
        label.lineBreakMode = .byTruncatingTail
        return label
    }

    func previewView(forAddress address: OWSContactAddress) -> UIView {

        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.alignment = .leading
        stackView.spacing = 0
        stackView.layoutMargins = .zero

        let tryToAddNameValue: ((String, String?) -> Void) = { (name, value) in
            guard let value = value else {
                return
            }
            guard value.count > 0 else {
                return
            }
            let row = UIView.container()

            let nameLabel = UILabel()
            nameLabel.text = name
            nameLabel.font = UIFont.ows_dynamicTypeCaption1
            nameLabel.textColor = UIColor.black
            nameLabel.lineBreakMode = .byTruncatingTail
            row.addSubview(nameLabel)
            nameLabel.autoPinLeadingToSuperviewMargin()
            nameLabel.autoPinHeightToSuperview()
            nameLabel.setContentHuggingHigh()
            nameLabel.setCompressionResistanceHigh()

            let valueLabel = UILabel()
            valueLabel.text = value
            valueLabel.font = UIFont.ows_dynamicTypeCaption1
            valueLabel.textColor = UIColor.ows_materialBlue
            valueLabel.lineBreakMode = .byTruncatingTail
            row.addSubview(valueLabel)
            valueLabel.autoPinLeading(toTrailingEdgeOf: nameLabel, offset: 10)
            valueLabel.autoPinTrailingToSuperviewMargin()
            valueLabel.autoPinHeightToSuperview()

            stackView.addArrangedSubview(row)
        }

        tryToAddNameValue(NSLocalizedString("CONTACT_FIELD_ADDRESS_STREET", comment: "Label for the 'street' field of a contact's address."),
                          address.street)
        tryToAddNameValue(NSLocalizedString("CONTACT_FIELD_ADDRESS_POBOX", comment: "Label for the 'pobox' field of a contact's address."),
                          address.pobox)
        tryToAddNameValue(NSLocalizedString("CONTACT_FIELD_ADDRESS_NEIGHBORHOOD", comment: "Label for the 'neighborhood' field of a contact's address."),
                          address.neighborhood)
        tryToAddNameValue(NSLocalizedString("CONTACT_FIELD_ADDRESS_CITY", comment: "Label for the 'city' field of a contact's address."),
                          address.city)
        tryToAddNameValue(NSLocalizedString("CONTACT_FIELD_ADDRESS_REGION", comment: "Label for the 'region' field of a contact's address."),
                          address.region)
        tryToAddNameValue(NSLocalizedString("CONTACT_FIELD_ADDRESS_POSTCODE", comment: "Label for the 'postcode' field of a contact's address."),
                          address.postcode)
        tryToAddNameValue(NSLocalizedString("CONTACT_FIELD_ADDRESS_COUNTRY", comment: "Label for the 'country' field of a contact's address."),
                          address.country)

        return stackView
    }

    // MARK: -

    func filteredContactShare() -> OWSContact {
        let result = self.contactShare.newContact(withNamePrefix: self.contactShare.namePrefix,
                                                  givenName: self.contactShare.givenName,
                                                  middleName: self.contactShare.middleName,
                                                  familyName: self.contactShare.familyName,
                                                  nameSuffix: self.contactShare.nameSuffix)

        for fieldView in fieldViews {
            if fieldView.field.isIncluded() {
                fieldView.field.applyToContact(contact: result)
            }
        }

        return result
    }

    // MARK: -

    func didPressSendButton() {
        Logger.info("\(logTag) \(#function)")

        guard let delegate = self.delegate else {
            owsFail("\(logTag) missing delegate.")
            return
        }

        let filteredContactShare = self.filteredContactShare()
        assert(filteredContactShare.ows_isValid())

        delegate.approveContactShare(self, didApproveContactShare: filteredContactShare)
    }

    func didPressCancel() {
        Logger.info("\(logTag) \(#function)")

        guard let delegate = self.delegate else {
            owsFail("\(logTag) missing delegate.")
            return
        }

        delegate.approveContactShare(self, didCancelContactShare: contactShare)
    }

    func didPressEditName() {
        Logger.info("\(logTag) \(#function)")

        let view = EditContactShareNameViewController(contactShare: contactShare, delegate: self)
        self.navigationController?.pushViewController(view, animated: true)
    }

    // MARK: - EditContactShareNameViewControllerDelegate

    public func editContactShareNameView(_ editContactShareNameView: EditContactShareNameViewController, didEditContactShare contactShare: OWSContact) {
        self.contactShare = contactShare

        nameLabel.text = contactShare.displayName

        self.updateNavigationBar()
    }
}
