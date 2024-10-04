//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalUI
import SignalServiceKit

class NicknameEditorViewController: OWSTableViewController2 {

    // MARK: Properties

    static let maxNoteLengthGlyphs: Int = 240
    static let maxNoteLengthBytes: Int = 2048

    struct Context {
        let db: any DB
        let nicknameManager: any NicknameManager
    }

    private let context: Context

    /// The Nickname that was already set when the view appeared.
    private let initialNickname: ProfileName?
    /// The note that was already set when the view appeared.
    private var initialNote: String? {
        self.initialNicknameRecord?.note
    }

    private let recipient: SignalRecipient
    private let initialNicknameRecord: NicknameRecord?

    static func create(for address: SignalServiceAddress, context: Context, tx: DBReadTransaction) -> NicknameEditorViewController? {
        guard let recipient = DependenciesBridge.shared.recipientDatabaseTable.fetchRecipient(
            address: address,
            tx: tx
        ) else {
            owsFailDebug("Could not find recipient for address")
            return nil
        }

        let nickname = context.nicknameManager.fetchNickname(for: recipient, tx: tx)

        return NicknameEditorViewController(
            recipient: recipient,
            existingNickname: nickname,
            context: context
        )
    }

    init(
        recipient: SignalRecipient,
        existingNickname: NicknameRecord?,
        context: Context
    ) {
        self.recipient = recipient
        self.context = context

        self.initialNickname = .init(nicknameRecord: existingNickname)
        self.initialNicknameRecord = existingNickname

        super.init()

        if let initialNickname {
            self.givenNameTextField.text = initialNickname.givenName
            self.familyNameTextField.text = initialNickname.familyName
        }
        self.noteTextView.text = initialNote
    }

    /// The given name entered into the text field.
    private var givenName: String? {
        self.givenNameTextField.text?.nilIfEmpty
    }
    /// The family name entered into the text field.
    private var familyName: String? {
        self.familyNameTextField.text?.nilIfEmpty
    }
    /// The note entered into the text view.
    private var note: String? {
        self.noteTextView.text?.nilIfEmpty
    }

    /// The Nickname, if valid, that is entered into the text fields.
    private var enteredNickname: ProfileName? {
        ProfileName(givenName: self.givenName, familyName: self.familyName)
    }

    /// Whether there are unsaved changes to the Nickname or note.
    private var hasUnsavedChanges: Bool {
        self.note != self.initialNote ||
        // `enteredNickname` only has a value when the nickname is valid, so we can't just check against that.
        self.givenName != self.initialNickname?.givenName ||
        self.familyName != self.initialNickname?.familyName
    }

    /// Whether the entered nickname is in a state that can be saved, either valid or empty.
    private var enteredNicknameCanBeSaved: Bool {
        (familyName == nil && givenName == nil) || enteredNickname != nil
    }

    /// Whether both there are unsaved changes and those changes can be saved.
    private var canSaveChanges: Bool {
        hasUnsavedChanges && enteredNicknameCanBeSaved
    }

    // MARK: Views

    private lazy var avatarView: ConversationAvatarView = {
        let avatarView = ConversationAvatarView(
            sizeClass: .eightyEight,
            localUserDisplayMode: .asUser,
            badged: false
        )
        avatarView.updateWithSneakyTransactionIfNecessary { config in
            config.dataSource = .address(self.recipient.address)
        }
        return avatarView
    }()

    private lazy var avatarViewContainer: UIView = {
        let container = UIView.container()
        container.addSubview(avatarView)
        avatarView.autoCenterInSuperview()
        avatarView.autoPinWidthToSuperview(relation: .lessThanOrEqual)
        avatarView.autoPinHeightToSuperview(withMargin: 24, relation: .lessThanOrEqual)
        return container
    }()

    private lazy var givenNameTextField = self.createNameTextField(
        placeholder: OWSLocalizedString(
            "NICKNAME_EDITOR_GIVEN_NAME_PLACEHOLDER",
            comment: "Placeholder text it the text field for the given name in the profile nickname editor."
        )
    )
    private lazy var familyNameTextField = self.createNameTextField(
        placeholder: OWSLocalizedString(
            "NICKNAME_EDITOR_FAMILY_NAME_PLACEHOLDER",
            comment: "Placeholder text it the text field for the family name in the profile nickname editor."
        )
    )

    private lazy var noteTextView: TextViewWithPlaceholder = {
        let textView = TextViewWithPlaceholder()
        textView.placeholderText = OWSLocalizedString(
            "NICKNAME_EDITOR_NOTE_PLACEHOLDER",
            comment: "Placeholder text it the text box for the note in the profile nickname editor."
        )
        textView.delegate = self

        textView.addSubview(noteCharacterLimitLabel)
        noteCharacterLimitLabel.autoPinEdge(toSuperviewEdge: .trailing)
        noteCharacterLimitLabel.autoPinEdge(toSuperviewEdge: .bottom)

        return textView
    }()

    private lazy var noteCharacterLimitLabel: UILabel = {
        let label = UILabel()
        label.font = .dynamicTypeSubheadline
        label.isHidden = true
        return label
    }()

    private func createNameTextField(placeholder: String) -> OWSTextField {
        OWSTextField(
            placeholder: placeholder,
            spellCheckingType: .no,
            autocorrectionType: .no,
            clearButtonMode: .whileEditing,
            delegate: self,
            editingChanged: { [weak self] in
                self?.editingChanged()
            }
        )
    }

    private func editingChanged() {
        navigationItem.rightBarButtonItem?.isEnabled = canSaveChanges

        let glyphCount = noteTextView.text?.glyphCount ?? 0
        if glyphCount < 140 {
            noteCharacterLimitLabel.isHidden = true
        } else {
            noteCharacterLimitLabel.isHidden = false
            let remainingCharacters = Self.maxNoteLengthGlyphs - glyphCount
            noteCharacterLimitLabel.text = "\(remainingCharacters)"
            if remainingCharacters > 5 {
                noteCharacterLimitLabel.textColor = Theme.secondaryTextAndIconColor
            } else {
                noteCharacterLimitLabel.textColor = .ows_accentRed
            }
        }
    }

    private func updateFonts() {
        let font = UIFont.dynamicTypeSubheadlineClamped
        noteCharacterLimitLabel.font = font
        noteTextView.textContainerInset.trailing = NSAttributedString(
            string: noteCharacterLimitLabel.text ?? "",
            attributes: [.font: font]
        ).size().width + 8
    }

    // MARK: Lifecycle

    override func viewDidLoad() {
        self.shouldAvoidKeyboard = true

        super.viewDidLoad()
        self.updateTableContents()
        self.updateFonts()

        self.title = OWSLocalizedString(
            "NICKNAME_EDITOR_TITLE",
            comment: "The title for the profile nickname editor view."
        )
        navigationItem.leftBarButtonItem = .cancelButton(
            dismissingFrom: self,
            hasUnsavedChanges: { [weak self] in self?.hasUnsavedChanges }
        )
        navigationItem.rightBarButtonItem = .doneButton { [weak self] in
            self?.saveChanges()
        }
        editingChanged()

        if self.initialNicknameRecord == nil, self.initialNote == nil {
            givenNameTextField.becomeFirstResponder()
        }
    }

    override func contentSizeCategoryDidChange() {
        super.contentSizeCategoryDidChange()
        self.updateFonts()
    }

    private func updateTableContents() {
        let contents = OWSTableContents()

        let titleSection = OWSTableSection(
            title: nil, items: [],
            footerTitle: OWSLocalizedString(
                "NICKNAME_EDITOR_DESCRIPTION",
                comment: "The description below the title on the profile nickname editor view."
            )
        )
        contents.add(titleSection)

        let namesSectionItems: [OWSTableItem]

        let givenNameItem = OWSTableItem.textFieldItem(
            self.givenNameTextField,
            textColor: Theme.primaryTextColor
        )

        let familyNameItem = OWSTableItem.textFieldItem(
            self.familyNameTextField,
            textColor: Theme.primaryTextColor
        )

        if NSLocale.current.isCJKV {
            namesSectionItems = [familyNameItem, givenNameItem]
        } else {
            namesSectionItems = [givenNameItem, familyNameItem]
        }

        let namesSection = OWSTableSection(
            items: namesSectionItems,
            headerView: self.avatarViewContainer
        )
        contents.add(namesSection)

        contents.add(.init(items: [
            self.textViewItem(self.noteTextView),
        ]))

        if self.initialNicknameRecord != nil {
            contents.add(.init(items: [
                .item(
                    name: CommonStrings.deleteButton,
                    textColor: .ows_accentRed,
                    actionBlock: { [weak self] in
                        self?.showDeleteNicknameConfirmation()
                    }
                )
            ]))
        }

        self.contents = contents
    }

    // MARK: Handlers

    private func saveChanges() {
        guard self.canSaveChanges else {
            owsFail("Shouldn't be able to save")
        }

        let nickname = self.enteredNickname

        if nickname == nil, self.note == nil {
            // All fields are empty
            deleteNickname()
            return
        }

        guard let nicknameRecord = NicknameRecord(
            recipient: self.recipient,
            givenName: nickname?.givenName,
            familyName: nickname?.familyName,
            note: self.note
        ) else {
            owsFailBeta("Nickname record could not be initialized")
            return
        }

        self.context.db.write { tx in
            // A Storage Service sync might have happened while this was open,
            // so we can't make assumptions about whether to create or update
            // based only on `self.initialNicknameRecord`.
            context.nicknameManager.createOrUpdate(
                nicknameRecord: nicknameRecord,
                updateStorageServiceFor: self.recipient.uniqueId,
                tx: tx
            )
        }

        self.dismiss(animated: true)
    }

    private func showDeleteNicknameConfirmation() {
        OWSActionSheets.showConfirmationAlert(
            title: OWSLocalizedString(
                "NICKNAME_EDITOR_DELETE_CONFIRMATION_TITLE",
                comment: "The title for a prompt confirming that the user wants to delete the nickname and note."
            ),
            message: OWSLocalizedString(
                "NICKNAME_EDITOR_DELETE_CONFIRMATION_MESSAGE",
                comment: "The message for a prompt confirming that the user wants to delete the nickname and note."
            ),
            proceedTitle: CommonStrings.deleteButton,
            proceedStyle: .destructive,
            proceedAction: { [weak self] _ in
                self?.deleteNickname()
            },
            fromViewController: self
        )
    }

    private func deleteNickname() {
        guard let recipientRowID = self.recipient.id else { return }
        self.context.db.write { tx in
            self.context.nicknameManager.deleteNickname(
                recipientRowID: recipientRowID,
                updateStorageServiceFor: self.recipient.uniqueId,
                tx: tx
            )
        }

        self.dismiss(animated: true)
    }
}

extension NicknameEditorViewController: UITextFieldDelegate {
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        TextFieldHelper.textField(
            textField,
            shouldChangeCharactersInRange: range,
            replacementString: string,
            maxByteCount: OWSUserProfile.Constants.maxNameLengthBytes,
            maxGlyphCount: OWSUserProfile.Constants.maxNameLengthGlyphs
        )
    }
}

// MARK: - TextViewWithPlaceholderDelegate

extension NicknameEditorViewController: TextViewWithPlaceholderDelegate {
    func textViewDidUpdateText(_ textView: TextViewWithPlaceholder) {
        self.editingChanged()
        _textViewDidUpdateText(textView)
    }

    func textView(_ textView: TextViewWithPlaceholder, uiTextView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        TextViewHelper.textView(
            textView,
            shouldChangeTextIn: range,
            replacementText: text,
            maxByteCount: Self.maxNoteLengthBytes,
            maxGlyphCount: Self.maxNoteLengthGlyphs
        )
    }
}
