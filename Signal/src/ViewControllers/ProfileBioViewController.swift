//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

protocol ProfileBioViewControllerDelegate: class {
    func profileBioViewDidComplete(bio: String?,
                                   bioEmoji: String?)
}

// MARK: -

@objc
class ProfileBioViewController: OWSTableViewController {

    private weak var profileDelegate: ProfileBioViewControllerDelegate?

    private static func buildTextField() -> UITextField {
        if UIDevice.current.isIPhone5OrShorter {
            return DismissableTextField()
        } else {
            return OWSTextField()
        }
    }

    private lazy var bioTextField = Self.buildTextField()

    private let bioEmojiLabel = UILabel()

    private let addEmojiImageView = UIImageView()

    private let emojiContainerView = UIView.container()

    private let mode: ProfileViewMode

    private let originalBio: String?
    private let originalBioEmoji: String?

    required init(bio: String?,
                  bioEmoji: String?,
                  mode: ProfileViewMode,
                  profileDelegate: ProfileBioViewControllerDelegate) {

        self.originalBio = bio
        self.originalBioEmoji = bioEmoji
        self.mode = mode
        self.profileDelegate = profileDelegate

        super.init()

        self.bioTextField.text = bio
        self.bioEmojiLabel.text = bioEmoji
    }

    // MARK: - Orientation

    public override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        if UIDevice.current.isIPad {
            return .all
        }
        return mode == .registration ? .portrait : .allButUpsideDown
    }

    // MARK: -

    public override func loadView() {
        super.loadView()

        self.useThemeBackgroundColors = true

        updateNavigation()

        createViews()

        updateTableContents()
    }

    private var normalizedProfileBio: String? {
        bioTextField.text?.ows_stripped()
    }

    private var normalizedProfileBioEmoji: String? {
        bioEmojiLabel.text?.ows_stripped()
    }

    private var hasUnsavedChanges: Bool {
        (normalizedProfileBio != originalBio) || (normalizedProfileBioEmoji != originalBioEmoji)
    }

    private func updateNavigation() {
        if bioTextField.isFirstResponder,
           let normalizedProfileBio = self.normalizedProfileBio,
           !normalizedProfileBio.isEmpty {
            let remainingCharCount = max(0, OWSUserProfile.kMaxBioLengthChars - normalizedProfileBio.glyphCount)
            let titleFormat = NSLocalizedString("PROFILE_BIO_VIEW_TITLE_FORMAT",
                                                comment: "Title for the profile bio view. Embeds {{ the number of characters that can be added to the profile bio without hitting the length limit }}.")
            title = String(format: titleFormat, OWSFormat.formatInt(remainingCharCount))
        } else {
            title = NSLocalizedString("PROFILE_BIO_VIEW_TITLE", comment: "Title for the profile bio view.")
        }

        if hasUnsavedChanges {
            navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel,
                                                               target: self,
                                                               action: #selector(didTapCancel),
                                                               accessibilityIdentifier: "cancel_button")
            navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done,
                                                                target: self,
                                                                action: #selector(didTapDone),
                                                                accessibilityIdentifier: "done_button")
        } else {
            navigationItem.leftBarButtonItem = nil
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
        addEmojiImageView.setTemplateImageName("add-emoji-outline-24",
                                               tintColor: Theme.secondaryTextAndIconColor)
        addEmojiImageView.autoSetDimensions(to: .square(24))
        emojiContainerView.addSubview(bioEmojiLabel)
        emojiContainerView.addSubview(addEmojiImageView)
        bioEmojiLabel.autoCenterInSuperview()
        addEmojiImageView.autoCenterInSuperview()
        emojiContainerView.autoSetDimensions(to: .square(28))
        bioEmojiLabel.accessibilityIdentifier = "bio_emoji"
        addEmojiImageView.accessibilityIdentifier = "bio_emoji"
        updateEmojiViews()

        bioTextField.returnKeyType = .done
        bioTextField.placeholder = NSLocalizedString("PROFILE_BIO_VIEW_BIO_PLACEHOLDER",
                                                            comment: "Placeholder text for the bio field of the profile bio view.")
        bioTextField.delegate = self
        bioTextField.accessibilityIdentifier = "bio_textfield"
        bioTextField.addTarget(self, action: #selector(textFieldDidChange), for: .editingChanged)
        bioTextField.addTarget(self, action: #selector(textFieldDidChange), for: .editingDidBegin)
        bioTextField.addTarget(self, action: #selector(textFieldDidChange), for: .editingDidEnd)
    }

    func updateTableContents() {
        let contents = OWSTableContents()

        let bioEmojiLabel = self.bioEmojiLabel
        let emojiContainerView = self.emojiContainerView
        let bioTextField = self.bioTextField

        let bioSection = OWSTableSection()
        bioSection.customHeaderHeight = 32
        bioSection.customFooterHeight = 24
        bioSection.add(OWSTableItem(customCellBlock: { [weak self] () -> UITableViewCell in
            let cell = OWSTableItem.newCell()

            bioEmojiLabel.font = .ows_dynamicTypeBodyClamped
            bioEmojiLabel.textColor = Theme.primaryTextColor
            bioEmojiLabel.setContentHuggingHorizontalHigh()
            bioEmojiLabel.setCompressionResistanceHorizontalHigh()

            bioTextField.font = .ows_dynamicTypeBodyClamped
            bioTextField.textColor = Theme.primaryTextColor
            bioTextField.setContentHuggingHorizontalLow()
            bioTextField.setCompressionResistanceHorizontalLow()

            let cancelColor = Theme.isDarkThemeEnabled ? UIColor.ows_gray45 : UIColor.ows_gray25
            let cancelIcon = UIImageView.withTemplateImageName("x-circle-filled-28",
                                                               tintColor: cancelColor)
            let cancelButton = OWSButton {
                self?.didTapResetButton()
            }
            cancelIcon.autoSetDimensions(to: .square(16))
            cancelButton.autoSetDimensions(to: .square(28))
            cancelButton.addSubview(cancelIcon)
            cancelIcon.autoCenterInSuperview()

            let stackView = UIStackView(arrangedSubviews: [emojiContainerView, bioTextField, cancelButton])
            stackView.axis = .horizontal
            stackView.alignment = .center
            stackView.spacing = 10
            cell.contentView.addSubview(stackView)
            stackView.autoPinEdgesToSuperviewMargins()

            return cell
        },
        actionBlock: { [weak self] in
            self?.didTapEmoji()
        }))
        contents.addSection(bioSection)

        let defaultBiosSection = OWSTableSection()
        for defaultBio in DefaultBio.values {
            defaultBiosSection.add(OWSTableItem(customCellBlock: { () -> UITableViewCell in
                let cell = OWSTableItem.newCell()

                let emojiLabel = UILabel()
                emojiLabel.text = defaultBio.emoji
                emojiLabel.font = .ows_dynamicTypeBodyClamped
                emojiLabel.textColor = Theme.primaryTextColor

                let bioLabel = UILabel()
                bioLabel.text = defaultBio.bio
                bioLabel.font = .ows_dynamicTypeBodyClamped
                bioLabel.textColor = Theme.primaryTextColor

                emojiLabel.setContentHuggingHorizontalHigh()
                emojiLabel.setCompressionResistanceHorizontalHigh()

                bioLabel.setContentHuggingHorizontalLow()
                bioLabel.setCompressionResistanceHorizontalLow()

                let stackView = UIStackView(arrangedSubviews: [emojiLabel, bioLabel])
                stackView.axis = .horizontal
                stackView.alignment = .center
                stackView.spacing = 10
                cell.contentView.addSubview(stackView)
                stackView.autoPinEdgesToSuperviewMargins()

                return cell
            },
            actionBlock: { [weak self] in
                self?.didTapDefaultBio(defaultBio)
            }))
        }
        contents.addSection(defaultBiosSection)

        self.contents = contents
    }

    struct DefaultBio {
        let emoji: String
        let bio: String

        static let values = [
            DefaultBio(emoji: "👍",
                       bio: NSLocalizedString("PROFILE_BIO_VIEW_DEFAULT_BIO_FREE_TO_CHAT",
                                              comment: "The 'free to chat' default bio in the profile bio view.")),
            DefaultBio(emoji: "☕",
                       bio: NSLocalizedString("PROFILE_BIO_VIEW_DEFAULT_BIO_COFFEE_LOVER",
                                              comment: "The 'Coffee lover' default bio in the profile bio view.")),
            DefaultBio(emoji: "✈️",
                       bio: NSLocalizedString("PROFILE_BIO_VIEW_DEFAULT_BIO_GLOBETROTTER",
                                              comment: "The 'Globetrotter' default bio in the profile bio view.")),
            DefaultBio(emoji: "📵",
                       bio: NSLocalizedString("PROFILE_BIO_VIEW_DEFAULT_BIO_TAKING_A_BREAK",
                                              comment: "The 'Taking a break' default bio in the profile bio view.")),
            DefaultBio(emoji: "🙏",
                       bio: NSLocalizedString("PROFILE_BIO_VIEW_DEFAULT_BIO_BE_KIND",
                                              comment: "The 'Be kind' default bio in the profile bio view.")),
            DefaultBio(emoji: "🚀",
                       bio: NSLocalizedString("PROFILE_BIO_VIEW_DEFAULT_BIO_WORKING_ON_SOMETHING_NEW",
                                              comment: "The 'Working on something new' default bio in the profile bio view."))
        ]
    }

    @objc
    func didTapCancel() {
        navigationController?.popViewController(animated: true)
    }

    @objc
    func didTapDone() {
        profileDelegate?.profileBioViewDidComplete(bio: normalizedProfileBio,
                                                   bioEmoji: normalizedProfileBioEmoji)

        navigationController?.popViewController(animated: true)
    }

    private func didTapEmoji() {
        // TODO
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
            replacementString: string.withoutBidiControlCharacters,
            maxByteCount: OWSUserProfile.kMaxBioLengthBytes,
            maxCharacterCount: OWSUserProfile.kMaxBioLengthChars
        )
    }

    @objc
    func textFieldDidChange(_ textField: UITextField) {
        updateNavigation()
    }
}
