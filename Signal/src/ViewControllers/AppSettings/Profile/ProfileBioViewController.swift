//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

protocol ProfileBioViewControllerDelegate: AnyObject {
    func profileBioViewDidComplete(bio: String?, bioEmoji: String?)
}

// MARK: -

final class ProfileBioViewController: OWSTableViewController2 {

    private weak var profileDelegate: ProfileBioViewControllerDelegate?

    private lazy var bioTextField = OWSTextField(
        placeholder: OWSLocalizedString(
            "PROFILE_BIO_VIEW_BIO_PLACEHOLDER",
            comment: "Placeholder text for the bio field of the profile bio view."
        ),
        returnKeyType: .done,
        delegate: self,
        editingChanged: { [weak self] in
            self?.updateNavigation()
        }
    )
    private lazy var cancelButton = OWSButton { [weak self] in
        self?.didTapResetButton()
    }

    private let bioEmojiLabel = UILabel()

    private let addEmojiImageView = UIImageView()

    private let emojiButton = OWSButton()

    private let originalBio: String?
    private let originalBioEmoji: String?

    init(bio: String?,
         bioEmoji: String?,
         profileDelegate: ProfileBioViewControllerDelegate) {

        self.originalBio = bio
        self.originalBioEmoji = bioEmoji
        self.profileDelegate = profileDelegate

        super.init()
    }

    // MARK: -

    override func viewDidLoad() {
        super.viewDidLoad()

        bioTextField.text = originalBio
        bioEmojiLabel.text = originalBioEmoji

        shouldAvoidKeyboard = true
        createViews()
        defaultSeparatorInsetLeading = Self.cellHInnerMargin + Self.bioButtonHeight + OWSTableItem.iconSpacing

        updateNavigation()
        updateTableContents()
    }

    private var normalizedProfileBio: String? {
        return bioTextField.text?.strippedOrNil
    }

    private var normalizedProfileBioEmoji: String? {
        return bioEmojiLabel.text?.strippedOrNil
    }

    private var hasUnsavedChanges: Bool {
        (normalizedProfileBio != originalBio) || (normalizedProfileBioEmoji != originalBioEmoji)
    }
    // Don't allow interactive dismiss when there are unsaved changes.
    override var isModalInPresentation: Bool {
        get { hasUnsavedChanges }
        set {}
    }

    private func updateNavigation() {
        if bioTextField.isFirstResponder, let normalizedProfileBio {
            let remainingGlyphCount = max(0, OWSUserProfile.Constants.maxBioLengthGlyphs - normalizedProfileBio.glyphCount)
            let titleFormat = OWSLocalizedString(
                "PROFILE_BIO_VIEW_TITLE_FORMAT",
                comment: "Title for the profile bio view. Embeds {{ the number of characters that can be added to the profile bio without hitting the length limit }}."
            )
            title = String(format: titleFormat, OWSFormat.formatInt(remainingGlyphCount))
        } else {
            title = OWSLocalizedString("PROFILE_BIO_VIEW_TITLE", comment: "Title for the profile bio view.")
        }

        navigationItem.leftBarButtonItem = .cancelButton(
            dismissingFrom: self,
            hasUnsavedChanges: { [weak self] in self?.hasUnsavedChanges }
        )

        cancelButton.isHiddenInStackView = normalizedProfileBio?.isEmpty != false && normalizedProfileBioEmoji?.isEmpty != false

        if hasUnsavedChanges {
            navigationItem.rightBarButtonItem = .doneButton { [weak self] in
                self?.didTapDone()
            }
        } else {
            navigationItem.rightBarButtonItem = nil
        }
    }

    private func setEmoji(emoji: String?) {
        if let emoji = emoji {
            bioEmojiLabel.text = emoji.trimToGlyphCount(1)
        } else {
            bioEmojiLabel.text = nil
        }

        updateEmojiViews()
    }

    private func updateEmojiViews() {
        if bioEmojiLabel.text != nil {
            bioEmojiLabel.isHidden = false
            addEmojiImageView.isHidden = true
        } else {
            bioEmojiLabel.isHidden = true
            addEmojiImageView.isHidden = false
        }
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        updateNavigation()
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        updateNavigation()

        bioTextField.becomeFirstResponder()
    }

    private func createViews() {
        // To avoid a jarring re-layout when switching between the
        // "has emoji" and "no emoji" states, we use a container
        // which is large enough to contain the views both for
        // states.
        emojiButton.block = { [weak self] in
            self?.didTapEmojiButton()
        }
        addEmojiImageView.setTemplateImageName("emoji-plus", tintColor: Theme.secondaryTextAndIconColor)
        addEmojiImageView.autoSetDimensions(to: .square(Self.bioButtonHeight))
        emojiButton.addSubview(bioEmojiLabel)
        emojiButton.addSubview(addEmojiImageView)
        bioEmojiLabel.autoCenterInSuperview()
        addEmojiImageView.autoCenterInSuperview()
        emojiButton.autoSetDimensions(to: .square(Self.bioButtonHeight))
        bioEmojiLabel.accessibilityIdentifier = "bio_emoji"
        addEmojiImageView.accessibilityIdentifier = "bio_emoji"
        updateEmojiViews()

        let cancelColor = Theme.isDarkThemeEnabled ? UIColor.ows_gray45 : UIColor.ows_gray25
        let cancelIcon = UIImageView.withTemplateImageName("x-circle-fill-compact", tintColor: cancelColor)

        cancelIcon.autoSetDimensions(to: .square(16))
        cancelButton.autoSetDimensions(to: .square(Self.bioButtonHeight))
        cancelButton.addSubview(cancelIcon)
        cancelIcon.autoCenterInSuperview()
    }

    private static let bioButtonHeight: CGFloat = 24

    func updateTableContents() {
        let contents = OWSTableContents()

        let bioEmojiLabel = self.bioEmojiLabel
        let emojiButton = self.emojiButton
        let bioTextField = self.bioTextField
        let cancelButton = self.cancelButton

        let bioSection = OWSTableSection()
        bioSection.add(OWSTableItem(customCellBlock: {
            let cell = OWSTableItem.newCell()

            bioEmojiLabel.font = .dynamicTypeBodyClamped
            bioEmojiLabel.textColor = Theme.primaryTextColor
            bioEmojiLabel.setContentHuggingHorizontalHigh()
            bioEmojiLabel.setCompressionResistanceHorizontalHigh()

            bioTextField.textColor = Theme.primaryTextColor
            bioTextField.setContentHuggingHorizontalLow()
            bioTextField.setCompressionResistanceHorizontalLow()

            let stackView = UIStackView(arrangedSubviews: [emojiButton, bioTextField, cancelButton])
            stackView.axis = .horizontal
            stackView.alignment = .center
            stackView.spacing = OWSTableItem.iconSpacing
            cell.contentView.addSubview(stackView)
            stackView.autoPinEdgesToSuperviewMargins()

            return cell
        },
        actionBlock: nil))
        contents.add(bioSection)

        let defaultBiosSection = OWSTableSection()
        for defaultBio in DefaultBio.values {
            defaultBiosSection.add(OWSTableItem(customCellBlock: {
                let cell = OWSTableItem.newCell()

                let emojiLabel = UILabel()
                emojiLabel.text = defaultBio.emoji
                emojiLabel.font = .dynamicTypeBodyClamped
                emojiLabel.textColor = Theme.primaryTextColor

                let bioLabel = UILabel()
                bioLabel.text = defaultBio.bio
                bioLabel.font = .dynamicTypeBodyClamped
                bioLabel.textColor = Theme.primaryTextColor

                emojiLabel.setContentHuggingHorizontalHigh()
                emojiLabel.setCompressionResistanceHorizontalHigh()

                bioLabel.setContentHuggingHorizontalLow()
                bioLabel.setCompressionResistanceHorizontalLow()

                let stackView = UIStackView(arrangedSubviews: [emojiLabel, bioLabel])
                stackView.axis = .horizontal
                stackView.alignment = .center
                stackView.spacing = OWSTableItem.iconSpacing
                cell.contentView.addSubview(stackView)
                stackView.autoPinEdgesToSuperviewMargins()

                return cell
            },
            actionBlock: { [weak self] in
                self?.didTapDefaultBio(defaultBio)
            }))
        }
        contents.add(defaultBiosSection)

        self.contents = contents
    }

    struct DefaultBio {
        let emoji: String
        let bio: String

        static let values = [
            DefaultBio(emoji: "👋",
                       bio: OWSLocalizedString("PROFILE_BIO_VIEW_DEFAULT_BIO_SPEAK_FREELY",
                                              comment: "The 'Speak Freely' default bio in the profile bio view.")),
            DefaultBio(emoji: "🤐",
                       bio: OWSLocalizedString("PROFILE_BIO_VIEW_DEFAULT_BIO_ENCRYPTED",
                                              comment: "The 'Encrypted' default bio in the profile bio view.")),
            DefaultBio(emoji: "👍",
                       bio: OWSLocalizedString("PROFILE_BIO_VIEW_DEFAULT_BIO_FREE_TO_CHAT",
                                              comment: "The 'free to chat' default bio in the profile bio view.")),
            DefaultBio(emoji: "☕",
                       bio: OWSLocalizedString("PROFILE_BIO_VIEW_DEFAULT_BIO_COFFEE_LOVER",
                                              comment: "The 'Coffee lover' default bio in the profile bio view.")),
            DefaultBio(emoji: "📵",
                       bio: OWSLocalizedString("PROFILE_BIO_VIEW_DEFAULT_BIO_TAKING_A_BREAK",
                                              comment: "The 'Taking a break' default bio in the profile bio view.")),
            DefaultBio(emoji: "🙏",
                       bio: OWSLocalizedString("PROFILE_BIO_VIEW_DEFAULT_BIO_BE_KIND",
                                              comment: "The 'Be kind' default bio in the profile bio view.")),
            DefaultBio(emoji: "🚀",
                       bio: OWSLocalizedString("PROFILE_BIO_VIEW_DEFAULT_BIO_WORKING_ON_SOMETHING_NEW",
                                              comment: "The 'Working on something new' default bio in the profile bio view."))
        ]
    }

    private func didTapDone() {
        profileDelegate?.profileBioViewDidComplete(bio: normalizedProfileBio, bioEmoji: normalizedProfileBioEmoji)

        dismiss(animated: true)
    }

    private func didTapEmojiButton() {
        showAnyEmojiPicker()
    }

    private var anyReactionPicker: EmojiPickerSheet?

    private func showAnyEmojiPicker() {
        let picker = EmojiPickerSheet(message: nil, allowReactionConfiguration: false) { [weak self] emoji in
            guard let emoji = emoji else {
                return
            }
            self?.didSelectEmoji(emoji.rawValue)
        }
        anyReactionPicker = picker

        present(picker, animated: true)
    }

    private func didSelectEmoji(_ emoji: String?) {
        setEmoji(emoji: emoji)
        updateNavigation()
    }

    private func didTapDefaultBio(_ defaultBio: DefaultBio) {
        setEmoji(emoji: defaultBio.emoji)
        bioTextField.text = defaultBio.bio
        updateNavigation()
    }

    private func didTapResetButton() {
        setEmoji(emoji: nil)
        bioTextField.text = nil
        updateNavigation()
    }
}

// MARK: -

extension ProfileBioViewController: UITextFieldDelegate {

    public func textField(_ textField: UITextField,
                          shouldChangeCharactersIn range: NSRange,
                          replacementString string: String) -> Bool {
        TextFieldHelper.textField(
            textField,
            shouldChangeCharactersInRange: range,
            replacementString: string.withoutBidiControlCharacters(),
            maxByteCount: OWSUserProfile.Constants.maxBioLengthBytes,
            maxGlyphCount: OWSUserProfile.Constants.maxBioLengthGlyphs
        )
    }

    func textFieldDidBeginEditing(_ textField: UITextField) {
        updateNavigation()
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        updateNavigation()
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        didTapDone()
        return false
    }
}
