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

class ProfileBioViewController: OWSTableViewController2, UITextFieldDelegate {

    private weak var profileDelegate: ProfileBioViewControllerDelegate?

    private lazy var bioTextField = {
        let textField = OWSTextField(
            placeholder: OWSLocalizedString(
                "PROFILE_BIO_VIEW_BIO_PLACEHOLDER",
                comment: "Placeholder text for the bio field of the profile bio view.",
            ),
            returnKeyType: .done,
            delegate: self,
            editingChanged: { [weak self] in
                self?.updateNavigation()
            },
        )
        textField.textColor = .Signal.label
        textField.setContentHuggingHorizontalLow()
        textField.setCompressionResistanceHorizontalLow()
        return textField
    }()

    private lazy var resetButton = {
        var buttonConfiguration = UIButton.Configuration.plain()
        buttonConfiguration.image = UIImage(resource: .xCircleFillCompact)
        buttonConfiguration.baseForegroundColor = .Signal.tertiaryLabel
        buttonConfiguration.contentInsets = .init(margin: 4) // 16dp icon, 24 dp button size
        let button = UIButton(
            configuration: buttonConfiguration,
            primaryAction: UIAction { [weak self] _ in
                self?.didTapResetButton()
            },
        )
        button.setContentHuggingHorizontalHigh()
        button.setCompressionResistanceHorizontalHigh()
        return button
    }()

    private lazy var emojiButton = {
        var buttonConfig = UIButton.Configuration.plain()
        buttonConfig.contentInsets = .zero // "add emoji" icon is 24 dp which is what the button should be
        buttonConfig.baseForegroundColor = .Signal.secondaryLabel
        buttonConfig.titleTextAttributesTransformer = .defaultFont(.dynamicTypeBodyClamped)

        let button = UIButton(
            configuration: buttonConfig,
            primaryAction: UIAction { [weak self] _ in
                self?.didTapEmojiButton()
            },
        )
        button.setContentHuggingHorizontalHigh()
        button.setCompressionResistanceHorizontalHigh()
        return button
    }()

    private let originalBio: String?
    private let originalBioEmoji: String?

    init(
        bio: String?,
        bioEmoji: String?,
        profileDelegate: ProfileBioViewControllerDelegate,
    ) {

        self.originalBio = bio
        self.originalBioEmoji = bioEmoji
        self.profileDelegate = profileDelegate

        super.init()
    }

    // MARK: -

    override func viewDidLoad() {
        super.viewDidLoad()

        setEmoji(emoji: originalBioEmoji)
        bioTextField.text = originalBio

        shouldAvoidKeyboard = true
        defaultSeparatorInsetLeading = Self.cellHInnerMargin + Self.bioButtonHeight + OWSTableItem.iconSpacing

        navigationItem.leftBarButtonItem = .cancelButton(
            dismissingFrom: self,
            hasUnsavedChanges: { [weak self] in self?.hasUnsavedChanges },
        )
        navigationItem.rightBarButtonItem = .setButton { [weak self] in
            self?.didTapDone()
        }

        updateNavigation()
        updateTableContents()
    }

    private var normalizedProfileBio: String? {
        return bioTextField.text?.strippedOrNil
    }

    private var normalizedProfileBioEmoji: String? {
        return emojiButton.configuration?.title?.strippedOrNil
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
                comment: "Title for the profile bio view. Embeds {{ the number of characters that can be added to the profile bio without hitting the length limit }}.",
            )
            title = String.nonPluralLocalizedStringWithFormat(titleFormat, OWSFormat.formatInt(remainingGlyphCount))
        } else {
            title = OWSLocalizedString("PROFILE_BIO_VIEW_TITLE", comment: "Title for the profile bio view.")
        }

        resetButton.isHiddenInStackView = normalizedProfileBio?.isEmpty != false && normalizedProfileBioEmoji?.isEmpty != false

        navigationItem.rightBarButtonItem?.isEnabled = hasUnsavedChanges
    }

    private func setEmoji(emoji: String?) {
        var buttonConfig = emojiButton.configuration ?? .plain()
        if let emoji = emoji?.trimToGlyphCount(1) {
            buttonConfig.image = nil
            buttonConfig.title = emoji
        } else {
            buttonConfig.image = UIImage(resource: .emojiPlus)
            buttonConfig.title = nil
        }
        emojiButton.configuration = buttonConfig
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        updateNavigation()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        bioTextField.becomeFirstResponder()
    }

    private static let bioButtonHeight: CGFloat = 24

    func updateTableContents() {
        let contents = OWSTableContents()

        let emojiButton = self.emojiButton
        let bioTextField = self.bioTextField
        let resetButton = self.resetButton

        let bioSection = OWSTableSection()
        bioSection.add(OWSTableItem(
            customCellBlock: {
                let cell = OWSTableItem.newCell()

                let stackView = UIStackView(arrangedSubviews: [emojiButton, bioTextField, resetButton])
                stackView.axis = .horizontal
                stackView.alignment = .center
                stackView.spacing = OWSTableItem.iconSpacing
                cell.contentView.addSubview(stackView)
                stackView.autoPinEdgesToSuperviewMargins()

                return cell
            },
        ))
        contents.add(bioSection)

        let defaultBiosSection = OWSTableSection()
        for defaultBio in DefaultBio.values {
            defaultBiosSection.add(OWSTableItem(
                customCellBlock: {
                    let cell = OWSTableItem.newCell()

                    let emojiLabel = UILabel()
                    emojiLabel.text = defaultBio.emoji
                    emojiLabel.font = .dynamicTypeBodyClamped
                    emojiLabel.textColor = .Signal.label
                    emojiLabel.setContentHuggingHorizontalHigh()
                    emojiLabel.setCompressionResistanceHorizontalHigh()

                    let bioLabel = UILabel()
                    bioLabel.text = defaultBio.bio
                    bioLabel.font = .dynamicTypeBodyClamped
                    bioLabel.textColor = .Signal.label
                    bioLabel.setContentHuggingHorizontalLow()
                    bioLabel.setCompressionResistanceHorizontalLow()

                    let stackView = UIStackView(arrangedSubviews: [emojiLabel, bioLabel])
                    stackView.alignment = .center
                    stackView.spacing = OWSTableItem.iconSpacing
                    cell.contentView.addSubview(stackView)
                    stackView.autoPinEdgesToSuperviewMargins()

                    return cell
                },
                actionBlock: { [weak self] in
                    self?.didTapDefaultBio(defaultBio)
                },
            ))
        }
        contents.add(defaultBiosSection)

        self.contents = contents
    }

    struct DefaultBio {
        let emoji: String
        let bio: String

        static let values = [
            DefaultBio(
                emoji: "👋",
                bio: OWSLocalizedString(
                    "PROFILE_BIO_VIEW_DEFAULT_BIO_SPEAK_FREELY",
                    comment: "The 'Speak Freely' default bio in the profile bio view.",
                ),
            ),
            DefaultBio(
                emoji: "🤐",
                bio: OWSLocalizedString(
                    "PROFILE_BIO_VIEW_DEFAULT_BIO_ENCRYPTED",
                    comment: "The 'Encrypted' default bio in the profile bio view.",
                ),
            ),
            DefaultBio(
                emoji: "👍",
                bio: OWSLocalizedString(
                    "PROFILE_BIO_VIEW_DEFAULT_BIO_FREE_TO_CHAT",
                    comment: "The 'free to chat' default bio in the profile bio view.",
                ),
            ),
            DefaultBio(
                emoji: "☕",
                bio: OWSLocalizedString(
                    "PROFILE_BIO_VIEW_DEFAULT_BIO_COFFEE_LOVER",
                    comment: "The 'Coffee lover' default bio in the profile bio view.",
                ),
            ),
            DefaultBio(
                emoji: "📵",
                bio: OWSLocalizedString(
                    "PROFILE_BIO_VIEW_DEFAULT_BIO_TAKING_A_BREAK",
                    comment: "The 'Taking a break' default bio in the profile bio view.",
                ),
            ),
            DefaultBio(
                emoji: "🙏",
                bio: OWSLocalizedString(
                    "PROFILE_BIO_VIEW_DEFAULT_BIO_BE_KIND",
                    comment: "The 'Be kind' default bio in the profile bio view.",
                ),
            ),
            DefaultBio(
                emoji: "🚀",
                bio: OWSLocalizedString(
                    "PROFILE_BIO_VIEW_DEFAULT_BIO_WORKING_ON_SOMETHING_NEW",
                    comment: "The 'Working on something new' default bio in the profile bio view.",
                ),
            ),
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
            guard let emoji else {
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

    // MARK: - UITextFieldDelegate

    func textField(
        _ textField: UITextField,
        shouldChangeCharactersIn range: NSRange,
        replacementString string: String,
    ) -> Bool {
        TextFieldHelper.textField(
            textField,
            shouldChangeCharactersInRange: range,
            replacementString: string.withoutBidiControlCharacters(),
            maxByteCount: OWSUserProfile.Constants.maxBioLengthBytes,
            maxGlyphCount: OWSUserProfile.Constants.maxBioLengthGlyphs,
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
