//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit

@objc
public protocol ApproveContactShareViewControllerDelegate: class {
    func approveContactShare(_ approveContactShare: ApproveContactShareViewController, didApproveContactShare contactShare: ContactShareViewModel)
    func approveContactShare(_ approveContactShare: ApproveContactShareViewController, didCancelContactShare contactShare: ContactShareViewModel)
}

protocol ContactShareField: class {

    func localizedLabel() -> String

    func isIncluded() -> Bool

    func setIsIncluded(_ isIncluded: Bool)

    func applyToContact(contact: ContactShareViewModel)
}

// MARK: -

class ContactShareFieldBase<ContactFieldType: OWSContactField>: NSObject, ContactShareField {

    let value: ContactFieldType

    private var isIncludedFlag = true

    required init(_ value: ContactFieldType) {
        self.value = value

        super.init()
    }

    func localizedLabel() -> String {
        return value.localizedLabel()
    }

    func isIncluded() -> Bool {
        return isIncludedFlag
    }

    func setIsIncluded(_ isIncluded: Bool) {
        isIncludedFlag = isIncluded
    }

    func applyToContact(contact: ContactShareViewModel) {
        preconditionFailure("This method must be overridden")
    }
}

// MARK: -

class ContactSharePhoneNumber: ContactShareFieldBase<OWSContactPhoneNumber> {

    override func applyToContact(contact: ContactShareViewModel) {
        assert(isIncluded())

        var values = [OWSContactPhoneNumber]()
        values += contact.phoneNumbers
        values.append(value)
        contact.phoneNumbers = values
    }
}

// MARK: -

class ContactShareEmail: ContactShareFieldBase<OWSContactEmail> {

    override func applyToContact(contact: ContactShareViewModel) {
        assert(isIncluded())

        var values = [OWSContactEmail]()
        values += contact.emails
        values.append(value)
        contact.emails = values
    }
}

// MARK: -

class ContactShareAddress: ContactShareFieldBase<OWSContactAddress> {

    override func applyToContact(contact: ContactShareViewModel) {
        assert(isIncluded())

        var values = [OWSContactAddress]()
        values += contact.addresses
        values.append(value)
        contact.addresses = values
    }
}

// MARK: -

protocol ContactShareFieldViewDelegate: class {
    func contactShareFieldViewDidChangeSelectedState()
}

// MARK: -

class ContactShareFieldView: UIStackView {

    weak var delegate: ContactShareFieldViewDelegate?

    let field: ContactShareField

    let previewViewBlock : (() -> UIView)

    private var checkbox: UIButton!

    // MARK: - Initializers

    @available(*, unavailable, message: "use init(call:) constructor instead.")
    required init(coder aDecoder: NSCoder) {
        fatalError("Unimplemented")
    }

    required init(field: ContactShareField, previewViewBlock : @escaping (() -> UIView), delegate: ContactShareFieldViewDelegate) {
        self.field = field
        self.previewViewBlock = previewViewBlock
        self.delegate = delegate

        super.init(frame: CGRect.zero)

        self.isUserInteractionEnabled = true
        self.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(wasTapped)))

        createContents()
    }

    let hSpacing = CGFloat(10)
    let hMargin = CGFloat(16)

    func createContents() {
        self.axis = .horizontal
        self.spacing = hSpacing
        self.alignment = .center
        self.layoutMargins = UIEdgeInsets(top: 0, left: hMargin, bottom: 0, right: hMargin)
        self.isLayoutMarginsRelativeArrangement = true

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
        self.addArrangedSubview(checkbox)
        checkbox.setCompressionResistanceHigh()
        checkbox.setContentHuggingHigh()

        let previewView = previewViewBlock()
        self.addArrangedSubview(previewView)
    }

    func wasTapped(sender: UIGestureRecognizer) {
        Logger.info("\(self.logTag) \(#function)")

        guard sender.state == .recognized else {
            return
        }
        field.setIsIncluded(!field.isIncluded())
        checkbox.isSelected = field.isIncluded()

        delegate?.contactShareFieldViewDidChangeSelectedState()
    }
}

// MARK: -

// TODO: Rename to ContactShareApprovalViewController
@objc
public class ApproveContactShareViewController: OWSViewController, EditContactShareNameViewControllerDelegate, ContactShareFieldViewDelegate {

    weak var delegate: ApproveContactShareViewControllerDelegate?

    let contactsManager: OWSContactsManager

    var contactShare: ContactShareViewModel

    var fieldViews = [ContactShareFieldView]()

    var nameLabel: UILabel!

    // MARK: Initializers

    @available(*, unavailable, message:"use other constructor instead.")
    required public init?(coder aDecoder: NSCoder) {
        fatalError("unimplemented")
    }

    @objc
    required public init(contactShare: ContactShareViewModel, contactsManager: OWSContactsManager, delegate: ApproveContactShareViewControllerDelegate) {
        self.contactsManager = contactsManager
        self.contactShare = contactShare
        self.delegate = delegate

        super.init(nibName: nil, bundle: nil)

        buildFields()
    }

    func buildFields() {
        var fieldViews = [ContactShareFieldView]()

        // TODO: Avatar

        let previewInsets = UIEdgeInsets(top: 5, left: 0, bottom: 5, right: 0)

        for phoneNumber in contactShare.phoneNumbers {
            let field = ContactSharePhoneNumber(phoneNumber)
            let fieldView = ContactShareFieldView(field: field, previewViewBlock: {
                return ContactFieldView.contactFieldView(forPhoneNumber: phoneNumber, layoutMargins: previewInsets, actionBlock: nil)
            },
                                                  delegate: self)
            fieldViews.append(fieldView)
        }

        for email in contactShare.emails {
            let field = ContactShareEmail(email)
            let fieldView = ContactShareFieldView(field: field, previewViewBlock: {
                return ContactFieldView.contactFieldView(forEmail: email, layoutMargins: previewInsets, actionBlock: nil)
            },
                                                  delegate: self)
            fieldViews.append(fieldView)
        }

        for address in contactShare.addresses {
            let field = ContactShareAddress(address)
            let fieldView = ContactShareFieldView(field: field, previewViewBlock: {
                return ContactFieldView.contactFieldView(forAddress: address, layoutMargins: previewInsets, actionBlock: nil)
            },
                                                  delegate: self)
            fieldViews.append(fieldView)
        }

        self.fieldViews = fieldViews
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

        self.view.backgroundColor = UIColor.white

        updateContent()

        updateNavigationBar()
    }

    // TODO: Surface error with resolution to user if not.
    func canShareContact() -> Bool {
        return contactShare.ows_isValid && isAtLeastOneFieldSelected()
    }

    func isAtLeastOneFieldSelected() -> Bool {
        for fieldView in fieldViews {
            if fieldView.field.isIncluded() {
                return true
            }
        }
        return false
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
        // Use layoutMarginsGuide for views inside UIScrollView
        // that should have same width as scroll view.
        fieldsView.autoPinLeadingToSuperviewMargin()
        fieldsView.autoPinTrailingToSuperviewMargin()
        fieldsView.autoPinEdge(toSuperviewEdge: .top)
        fieldsView.autoPinEdge(toSuperviewEdge: .bottom)
        fieldsView.setContentHuggingHorizontalLow()
    }

    private func createFieldsView() -> UIView {
        SwiftAssertIsOnMainThread(#function)

        var rows = [UIView]()

        rows.append(createNameRow())

        for fieldView in fieldViews {
            rows.append(fieldView)
        }

        return ContactFieldView(rows: rows, hMargin: hMargin)
    }

    private let hMargin = CGFloat(16)

    func createNameRow() -> UIView {
        let nameVMargin = CGFloat(16)

        let stackView = TappableStackView(actionBlock: { [weak self] _ in
            guard let strongSelf = self else { return }
            strongSelf.didPressEditName()
        })

        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.layoutMargins = UIEdgeInsets(top: nameVMargin, left: hMargin, bottom: nameVMargin, right: hMargin)
        stackView.spacing = 10
        stackView.isLayoutMarginsRelativeArrangement = true

        let nameLabel = UILabel()
        self.nameLabel = nameLabel
        nameLabel.text = contactShare.displayName
        nameLabel.font = UIFont.ows_dynamicTypeBody.ows_mediumWeight()
        nameLabel.textColor = UIColor.black
        nameLabel.lineBreakMode = .byTruncatingTail
        stackView.addArrangedSubview(nameLabel)

        let editNameLabel = UILabel()
        editNameLabel.text = NSLocalizedString("CONTACT_EDIT_NAME_BUTTON", comment: "Label for the 'edit name' button in the contact share approval view.")
        editNameLabel.font = UIFont.ows_dynamicTypeBody
        editNameLabel.textColor = UIColor.ows_materialBlue
        stackView.addArrangedSubview(editNameLabel)
        editNameLabel.setContentHuggingHigh()
        editNameLabel.setCompressionResistanceHigh()

        return stackView
    }

    // MARK: -

    func filteredContactShare() -> ContactShareViewModel {
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
        SwiftAssertIsOnMainThread(#function)
        assert(canShareContact())

        Logger.info("\(logTag) \(#function)")

        guard let delegate = self.delegate else {
            owsFail("\(logTag) missing delegate.")
            return
        }

        let filteredContactShare = self.filteredContactShare()
        assert(filteredContactShare.ows_isValid)

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

    public func editContactShareNameView(_ editContactShareNameView: EditContactShareNameViewController, didEditContactShare contactShare: ContactShareViewModel) {
        self.contactShare = contactShare

        nameLabel.text = contactShare.displayName

        self.updateNavigationBar()
    }

    // MARK: - ContactShareFieldViewDelegate

    public func contactShareFieldViewDidChangeSelectedState() {
        self.updateNavigationBar()
    }
}
