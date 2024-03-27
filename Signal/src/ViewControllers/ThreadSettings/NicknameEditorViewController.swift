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

    /// The Nickname that was already set when the view appeared.
    private var initialNickname: ProfileName?
    /// The note that was already set when the view appeared.
    private var initialNote: String?

    private let thread: TSContactThread

    init(
        thread: TSContactThread,
        initialNickname: ProfileName? = nil,
        initialNote: String? = nil
    ) {
        // [Nicknames] TODO: Read the initial values here instead of having them passed in
        self.thread = thread
        self.initialNickname = initialNickname
        self.initialNote = initialNote
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
            config.dataSource = .thread(self.thread)
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
        return textView
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
    }

    // MARK: Lifecycle

    override func viewDidLoad() {
        self.shouldAvoidKeyboard = true

        super.viewDidLoad()
        self.updateTableContents()
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

        self.contents = contents
    }

    // MARK: Handlers

    private func saveChanges() {
        // [Nicknames] TODO: Save nickname and note
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
