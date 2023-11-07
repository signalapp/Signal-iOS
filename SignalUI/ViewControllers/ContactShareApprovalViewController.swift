//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

public protocol ContactShareApprovalViewControllerDelegate: AnyObject {
    func approveContactShare(_ approveContactShare: ContactShareApprovalViewController,
                             didApproveContactShare contactShare: ContactShareViewModel)
    func approveContactShare(_ approveContactShare: ContactShareApprovalViewController,
                             didCancelContactShare contactShare: ContactShareViewModel)

    func contactApprovalCustomTitle(_ contactApproval: ContactShareApprovalViewController) -> String?

    func contactApprovalRecipientsDescription(_ contactApproval: ContactShareApprovalViewController) -> String?

    func contactApprovalMode(_ contactApproval: ContactShareApprovalViewController) -> ApprovalMode
}

// MARK: -

protocol ContactShareField: AnyObject {

    var isAvatar: Bool { get }

    func localizedLabel() -> String

    func isIncluded() -> Bool

    func setIsIncluded(_ isIncluded: Bool)

    func applyToContact(contact: ContactShareViewModel)
}

// MARK: -

class ContactShareFieldBase<ContactFieldType: OWSContactField>: NSObject, ContactShareField {

    let value: ContactFieldType

    private var isIncludedFlag = true

    var isAvatar: Bool { return false }

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
        fatalError("applyToContact(contact:) has not been implemented")
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

// Stub class so that avatars conform to OWSContactField.
class OWSContactAvatar: NSObject, OWSContactField {

    public let avatarImage: UIImage
    public let avatarData: Data

    required init(avatarImage: UIImage, avatarData: Data) {
        self.avatarImage = avatarImage
        self.avatarData = avatarData

        super.init()
    }

    public func ows_isValid() -> Bool {
        return true
    }

    public func localizedLabel() -> String {
        return ""
    }

    override public var debugDescription: String {
        return "Avatar"
    }
}

class ContactShareAvatarField: ContactShareFieldBase<OWSContactAvatar> {
    override var isAvatar: Bool { return true }

    override func applyToContact(contact: ContactShareViewModel) {
        assert(isIncluded())

        contact.avatarImageData = value.avatarData
    }
}

// MARK: -

protocol ContactShareFieldViewDelegate: AnyObject {
    func contactShareFieldViewDidChangeSelectedState()
}

// MARK: -

class ContactShareFieldView: UIStackView {

    weak var delegate: ContactShareFieldViewDelegate?

    let field: ContactShareField

    let previewViewBlock: (() -> UIView)

    private lazy var checkbox = UIButton(type: .custom)

    // MARK: - Initializers

    @available(*, unavailable, message: "use init(call:) constructor instead.")
    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    required init(field: ContactShareField, previewViewBlock: @escaping (() -> UIView), delegate: ContactShareFieldViewDelegate) {
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

        checkbox.setImage(Theme.iconImage(.circle), for: .normal)
        checkbox.setImage(Theme.iconImage(.checkCircleFill), for: .selected)
        checkbox.isSelected = field.isIncluded()
        // Disable the checkbox; the entire row is hot.
        checkbox.isUserInteractionEnabled = false
        addArrangedSubview(checkbox)
        checkbox.setCompressionResistanceHigh()
        checkbox.setContentHuggingHigh()

        let previewView = previewViewBlock()
        addArrangedSubview(previewView)
    }

    @objc
    private func wasTapped(sender: UIGestureRecognizer) {
        Logger.info("")

        guard sender.state == .recognized else {
            return
        }
        field.setIsIncluded(!field.isIncluded())
        checkbox.isSelected = field.isIncluded()

        delegate?.contactShareFieldViewDidChangeSelectedState()
    }
}

// MARK: -

public class ContactShareApprovalViewController: OWSViewController, EditContactShareNameViewControllerDelegate, ContactShareFieldViewDelegate {

    public weak var delegate: ContactShareApprovalViewControllerDelegate?

    var contactShare: ContactShareViewModel

    var fieldViews = [ContactShareFieldView]()

    var nameLabel: UILabel!

    private let footerView = ApprovalFooterView()

    private var approvalMode: ApprovalMode {
        guard let delegate = delegate else {
            return .send
        }
        return delegate.contactApprovalMode(self)
    }

    // MARK: - UIViewController

    public override var canBecomeFirstResponder: Bool {
        return true
    }

    var currentInputAcccessoryView: UIView? {
        didSet {
            if oldValue != currentInputAcccessoryView {
                reloadInputViews()
            }
        }
    }

    public override var inputAccessoryView: UIView? {
        return currentInputAcccessoryView
    }

    // MARK: Initializers

    required public init(contactShare: ContactShareViewModel) {
        self.contactShare = contactShare

        super.init()

        buildFields()
    }

    func buildFields() {
        var fieldViews = [ContactShareFieldView]()

        let previewInsets = UIEdgeInsets(top: 5, left: 0, bottom: 5, right: 0)

        if let avatarData = contactShare.avatarImageData {
            if let avatarImage = contactShare.avatarImage {
                let field = ContactShareAvatarField(OWSContactAvatar(avatarImage: avatarImage, avatarData: avatarData))
                let fieldView = ContactShareFieldView(field: field, previewViewBlock: {
                    return ContactFieldView.contactFieldView(forAvatarImage: avatarImage, layoutMargins: previewInsets, actionBlock: nil)
                },
                                                      delegate: self)
                fieldViews.append(fieldView)
            } else {
                owsFailDebug("could not load avatar image.")
            }
        }

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

        updateControls()
    }

    override public func loadView() {
        super.loadView()

        if let title = delegate?.contactApprovalCustomTitle(self) {
            self.navigationItem.title = title
        } else {
            self.navigationItem.title = OWSLocalizedString("CONTACT_SHARE_APPROVAL_VIEW_TITLE",
                                                          comment: "Title for the 'Approve contact share' view.")
        }

        self.view.backgroundColor = Theme.backgroundColor

        footerView.delegate = self

        updateContent()

        updateControls()
    }

    func isAtLeastOneFieldSelected() -> Bool {
        for fieldView in fieldViews {
            if fieldView.field.isIncluded(), !fieldView.field.isAvatar {
                return true
            }
        }
        return false
    }

    func updateControls() {
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel,
                                                                target: self,
                                                                action: #selector(didPressCancel))

        guard isAtLeastOneFieldSelected() else {
            currentInputAcccessoryView = nil
            return
        }
        guard let recipientsDescription = delegate?.contactApprovalRecipientsDescription(self) else {
            currentInputAcccessoryView = nil
            return
        }
        footerView.setNamesText(recipientsDescription, animated: false)
        currentInputAcccessoryView = footerView
    }

    private func updateContent() {
        AssertIsOnMainThread()

        guard let rootView = self.view else {
            owsFailDebug("missing root view.")
            return
        }

        for subview in rootView.subviews {
            subview.removeFromSuperview()
        }

        let scrollView = UIScrollView()
        scrollView.preservesSuperviewLayoutMargins = false
        self.view.addSubview(scrollView)
        scrollView.layoutMargins = .zero
        scrollView.autoPinEdge(toSuperviewSafeArea: .leading)
        scrollView.autoPinEdge(toSuperviewSafeArea: .trailing)
        scrollView.autoPin(toTopLayoutGuideOf: self, withInset: 0)
        scrollView.autoPinEdge(.bottom, to: .bottom, of: keyboardLayoutGuideViewSafeArea)

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
        AssertIsOnMainThread()

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

        let stackView = TappableStackView(actionBlock: { [weak self] in
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
        nameLabel.text = contactShare.name.displayName
        nameLabel.font = UIFont.dynamicTypeBody.semibold()
        nameLabel.textColor = Theme.primaryTextColor
        nameLabel.lineBreakMode = .byTruncatingTail
        stackView.addArrangedSubview(nameLabel)

        let editNameLabel = UILabel()
        editNameLabel.text = OWSLocalizedString("CONTACT_EDIT_NAME_BUTTON", comment: "Label for the 'edit name' button in the contact share approval view.")
        editNameLabel.font = UIFont.dynamicTypeBody
        editNameLabel.textColor = Theme.accentBlueColor
        stackView.addArrangedSubview(editNameLabel)
        editNameLabel.setContentHuggingHigh()
        editNameLabel.setCompressionResistanceHigh()

        return stackView
    }

    // MARK: -

    func filteredContactShare() -> ContactShareViewModel {
        let result = self.contactShare.newContact(withName: self.contactShare.name)

        for fieldView in fieldViews {
            if fieldView.field.isIncluded() {
                fieldView.field.applyToContact(contact: result)
            }
        }

        return result
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

        Logger.info("")

        guard let delegate = self.delegate else {
            owsFailDebug("missing delegate.")
            return
        }

        let filteredContactShare = self.filteredContactShare()

        assert(filteredContactShare.ows_isValid)

        delegate.approveContactShare(self, didApproveContactShare: filteredContactShare)
    }

    @objc
    private func didPressCancel() {
        Logger.info("")

        guard let delegate = self.delegate else {
            owsFailDebug("missing delegate.")
            return
        }

        delegate.approveContactShare(self, didCancelContactShare: contactShare)
    }

    private func didPressEditName() {
        Logger.info("")

        let view = EditContactShareNameViewController(contactShare: contactShare, delegate: self)
        self.navigationController?.pushViewController(view, animated: true)
    }

    // MARK: - EditContactShareNameViewControllerDelegate

    public func editContactShareNameView(_ editContactShareNameView: EditContactShareNameViewController,
                                         didEditContactShare contactShare: ContactShareViewModel) {
        self.contactShare = contactShare

        nameLabel.text = contactShare.name.displayName

        updateControls()
    }

    // MARK: - ContactShareFieldViewDelegate

    public func contactShareFieldViewDidChangeSelectedState() {
        updateControls()
    }
}

// MARK: -

extension ContactShareApprovalViewController: ApprovalFooterDelegate {
    public func approvalFooterDelegateDidRequestProceed(_ approvalFooterView: ApprovalFooterView) {
        didPressSendButton()
    }

    public func approvalMode(_ approvalFooterView: ApprovalFooterView) -> ApprovalMode {
        return approvalMode
    }

    public func approvalFooterDidBeginEditingText() {}
}
