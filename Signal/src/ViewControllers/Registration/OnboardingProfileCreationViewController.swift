//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class OnboardingProfileCreationViewController: OnboardingBaseViewController {

    // MARK: - Properties

    private var avatarData: Data?

    private var isValidProfile: Bool {
        !normalizedGivenName.isEmpty
    }

    private var normalizedGivenName: String {
        (givenNameTextField.text ?? "").ows_stripped()
    }

    private var normalizedFamilyName: String {
        (familyNameTextField.text ?? "").ows_stripped()
    }

    // MARK: - Views

    private let contentScrollView = UIScrollView()

    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.ows_dynamicTypeTitle1.ows_semibold
        label.adjustsFontForContentSizeCategory = true
        label.textAlignment = .center
        label.text = NSLocalizedString(
            "ONBOARDING_PROFILE_CREATION_TITLE",
            comment: "Title label for profile creation step of onboarding")
        label.numberOfLines = 0
        return label
    }()

    private let avatarSize: CGFloat = 64.0
    private lazy var avatarView: AvatarImageView = {
        let view = AvatarImageView()
        view.autoSetDimensions(to: CGSize.square(avatarSize))
        view.accessibilityIdentifier = "avatar_view"

        let avatarTapGesture = UITapGestureRecognizer(target: self, action: #selector(didTapAvatar))
        view.addGestureRecognizer(avatarTapGesture)
        view.isUserInteractionEnabled = true
        return view
    }()

    let cameraImageViewSize = CGSize(square: 32)
    private lazy var cameraImageView: UIImageView = {
        let cameraImageView = UIImageView.withTemplateImageName("camera-outline-24", tintColor: Theme.secondaryTextAndIconColor)
        cameraImageView.autoSetDimensions(to: cameraImageViewSize)
        cameraImageView.contentMode = .center
        cameraImageView.layer.cornerRadius = cameraImageViewSize.largerAxis / 2
        return cameraImageView
    }()

    private lazy var cameraImageShadowLayers: [CALayer] = {
        let finerShadowLayer = cameraImageView.layer
        let broaderShadowLayer = CALayer()
        finerShadowLayer.addSublayer(broaderShadowLayer)
        let shadowLayers = [finerShadowLayer, broaderShadowLayer]

        shadowLayers.forEach {
            $0.shadowPath = UIBezierPath(ovalIn: CGRect(origin: .zero, size: cameraImageViewSize)).cgPath
        }

        finerShadowLayer.shadowRadius = 4
        finerShadowLayer.shadowOffset = CGSize(width: 0, height: 2)
        finerShadowLayer.shadowOpacity = 0.2
        broaderShadowLayer.shadowRadius = 16
        broaderShadowLayer.shadowOffset = CGSize(width: 0, height: 4)
        broaderShadowLayer.shadowOpacity = 0.12
        return shadowLayers
    }()

    private lazy var givenNameTextField: OWSTextField = {
        let label = OWSTextField()
        label.font = .ows_dynamicTypeSubheadlineClamped
        label.adjustsFontForContentSizeCategory = true
        label.textAlignment = .natural
        label.autocorrectionType = .no
        label.spellCheckingType = .no
        label.textContentType = .givenName

        label.accessibilityIdentifier = "given_name_textfield"
        label.placeholder = NSLocalizedString(
            "ONBOARDING_PROFILE_GIVEN_NAME_FIELD",
            comment: "Placeholder text for the given name field of the profile creation view.")

        label.delegate = self
        label.addTarget(self, action: #selector(textFieldDidChange), for: .editingChanged)
        label.autoSetDimension(.height, toSize: 50, relation: .greaterThanOrEqual)
        return label
    }()

    private lazy var familyNameTextField: OWSTextField = {
        let label = OWSTextField()
        label.font = .ows_dynamicTypeSubheadlineClamped
        label.adjustsFontForContentSizeCategory = true
        label.textAlignment = .natural
        label.autocorrectionType = .no
        label.spellCheckingType = .no
        label.textContentType = .familyName

        label.accessibilityIdentifier = "family_name_textfield"
        label.placeholder = NSLocalizedString(
            "ONBOARDING_PROFILE_FAMILY_NAME_FIELD",
            comment: "Placeholder text for the family name field of the profile creation view.")

        label.delegate = self
        label.addTarget(self, action: #selector(textFieldDidChange), for: .editingChanged)
        label.autoSetDimension(.height, toSize: 50, relation: .greaterThanOrEqual)
        return label
    }()

    private lazy var nameFieldStrokes: [UIView] = [givenNameTextField, familyNameTextField].map {
        $0.addBottomStroke(color: Theme.cellSeparatorColor, strokeWidth: CGHairlineWidth())
    }

    // For CJKV locales, display family name field first
    private var firstTextField: UITextField { NSLocale.current.isCJKV ? familyNameTextField : givenNameTextField }
    private var secondTextField: UITextField { NSLocale.current.isCJKV ? givenNameTextField : familyNameTextField }

    private var footerText: NSAttributedString {
        let descriptionString = NSLocalizedString("PROFILE_VIEW_PROFILE_DESCRIPTION", comment: "Description of the user profile.")
        let spacerString = "  "
        let learnMoreString = CommonStrings.learnMore

        return NSAttributedString.composed(of: [
            descriptionString.styled(with: .font(.ows_dynamicTypeCaption1), .color(Theme.secondaryTextAndIconColor)),
            spacerString.styled(with: .font(. ows_dynamicTypeCaption1), .color(Theme.secondaryTextAndIconColor)),
            learnMoreString.styled(with:
                .link(URL(string: "https://support.signal.org/hc/articles/360007459591")!),
                .font(.ows_dynamicTypeCaption1),
                .color(Theme.accentBlueColor),
                .underline([], nil)
            )
        ])
    }

    private lazy var footerTextView: LinkingTextView = {
        let footerTextView = LinkingTextView()
        footerTextView.font = .ows_dynamicTypeCaption1
        footerTextView.adjustsFontForContentSizeCategory = true
        footerTextView.attributedText = footerText
        footerTextView.isUserInteractionEnabled = true
        return footerTextView
    }()

    private lazy var saveButtonBackdrop = UIView()
    private lazy var saveButtonGradient = GradientView(colors: [])

    private lazy var saveButton = self.primaryButton(
        title: NSLocalizedString("PROFILE_VIEW_SAVE_BUTTON",
                                 comment: "Button to save the profile view in the profile view."),
        selector: #selector(saveProfile)
    )

    static private let standardMargin: CGFloat = UIDevice.current.isIPhone5OrShorter ? 16 : 32

    // MARK: - Lifecycle

    public override func loadView() {
        // Build chrome
        view = UIView()
        view.addSubview(primaryView)
        primaryView.autoPinEdgesToSuperviewEdges()
        primaryView.insetsLayoutMarginsFromSafeArea = false

        primaryView.addSubview(contentScrollView)
        contentScrollView.autoPinEdgesToSuperviewEdges(with: .zero, excludingEdge: .bottom)
        autoPinView(toBottomOfViewControllerOrKeyboard: contentScrollView, avoidNotch: true)
        contentScrollView.preservesSuperviewLayoutMargins = true

        // Build stacks
        firstTextField.returnKeyType = .next
        secondTextField.returnKeyType = .done
        let nameStack = UIStackView(arrangedSubviews: [firstTextField, secondTextField])
        let profileStack = UIStackView(arrangedSubviews: [avatarView, nameStack])
        let outerStack = UIStackView(arrangedSubviews: [titleLabel, profileStack, footerTextView])

        nameStack.axis = .vertical
        nameStack.spacing = 0
        nameStack.alignment = .fill
        nameStack.distribution = .equalSpacing
        profileStack.axis = .horizontal
        profileStack.spacing = 24
        profileStack.alignment = .center
        profileStack.distribution = .fill
        outerStack.axis = .vertical
        outerStack.spacing = 32

        [nameStack, profileStack, outerStack].forEach {
            $0.preservesSuperviewLayoutMargins = true
            $0.isLayoutMarginsRelativeArrangement = true
        }

        // Most subviews get added to the scroll view
        contentScrollView.addSubview(outerStack)
        outerStack.autoPinWidth(toWidthOf: primaryView)
        outerStack.autoPinEdgesToSuperviewEdges()

        contentScrollView.addSubview(cameraImageView)
        cameraImageView.autoPinEdge(.bottom, to: .bottom, of: avatarView)
        cameraImageView.autoPinEdge(.trailing, to: .trailing, of: avatarView)

        // The save button will be pinned above the scroll view to the top of the keyboard
        saveButton.setEnabled(false)
        primaryView.addSubview(saveButtonGradient)
        primaryView.addSubview(saveButtonBackdrop)
        saveButtonBackdrop.addSubview(saveButton)

        saveButtonGradient.isUserInteractionEnabled = false
        saveButtonBackdrop.preservesSuperviewLayoutMargins = true
        saveButtonBackdrop.layoutMargins = UIEdgeInsets(top: 8, leading: 0, bottom: Self.standardMargin, trailing: 0)

        saveButton.autoPinEdgesToSuperviewMargins()
        saveButtonGradient.autoPinWidthToSuperview()
        saveButtonBackdrop.autoPinWidthToSuperview()

        saveButtonGradient.autoSetDimension(.height, toSize: 30)
        saveButtonGradient.autoPinEdge(.bottom, to: .top, of: saveButtonBackdrop)
        saveButtonBackdrop.autoPinEdge(.bottom, to: .bottom, of: contentScrollView)
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        shouldBottomViewReserveSpaceForKeyboard = false
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateAvatarView()
        applyTheme()
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !UIDevice.current.isIPhone5OrShorter {
            // Only become first responder on devices larger than iPhone 5s
            // 5s is prone to obscuring the profile description text behind the keyboard
            // At larger font sizes, it's not clear that it's scrollable.
            firstTextField.becomeFirstResponder()
        }
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        let bottomInsetHeight = saveButtonBackdrop.height + (saveButtonGradient.height / 2)
        if contentScrollView.contentInset.bottom < bottomInsetHeight {
            contentScrollView.contentInset.bottom = bottomInsetHeight
        }
    }

    public override func updateBottomLayoutConstraint(fromInset before: CGFloat, toInset after: CGFloat) {
        // Ignore any minor decreases in height. We want to grow to accomodate the
        // QuickType bar, but shrinking in response to its dismissal is a bit much.
        let isKeyboardDismissing = (after == 0)
        let isKeyboardGrowing = after > before
        let isKeyboardSignificantlyShrinking = ((before - after) / UIScreen.main.bounds.height) > 0.1

        if isKeyboardGrowing || isKeyboardSignificantlyShrinking || isKeyboardDismissing {
            super.updateBottomLayoutConstraint(fromInset: before, toInset: after)
        }
    }

    @objc
    public override func applyTheme() {
        super.applyTheme()

        UIView.transition(with: view, duration: 0.25, options: .transitionCrossDissolve) {
            self.view.backgroundColor = Theme.backgroundColor

            self.cameraImageView.tintColor = Theme.secondaryTextAndIconColor
            self.cameraImageView.backgroundColor = Theme.backgroundColor
            self.cameraImageShadowLayers.forEach {
                $0.shadowColor = (Theme.isDarkThemeEnabled ? Theme.darkThemeWashColor : UIColor.ows_black).cgColor
            }

            [self.givenNameTextField, self.familyNameTextField].forEach { $0.textColor = Theme.primaryTextColor }
            self.nameFieldStrokes.forEach { $0.backgroundColor = Theme.hairlineColor }

            // Text will be rebuilt with updated colors
            self.footerTextView.attributedText = self.footerText

            self.saveButtonBackdrop.backgroundColor = Theme.backgroundColor
            self.saveButtonGradient.colors = [
                (Theme.backgroundColor.withAlphaComponent(0), 0.0),
                (Theme.backgroundColor, 1.0)
            ]
        }
    }

    // MARK: - Event Handling

    @objc
    func saveProfile() {
        if normalizedGivenName.isEmpty {
            OWSActionSheets.showErrorAlert(message: NSLocalizedString("PROFILE_VIEW_ERROR_GIVEN_NAME_REQUIRED",
                                                                      comment: "Error message shown when user tries to update profile without a given name"))
            return
        }

        if profileManagerImpl.isProfileNameTooLong(normalizedGivenName) {
            OWSActionSheets.showErrorAlert(message: NSLocalizedString("PROFILE_VIEW_ERROR_GIVEN_NAME_TOO_LONG",
                                                                      comment: "Error message shown when user tries to update profile with a given name that is too long."))
            return
        }

        if profileManagerImpl.isProfileNameTooLong(normalizedFamilyName) {
            OWSActionSheets.showErrorAlert(message: NSLocalizedString("PROFILE_VIEW_ERROR_FAMILY_NAME_TOO_LONG",
                                                                      comment: "Error message shown when user tries to update profile with a family name that is too long."))
            return
        }

        if !self.reachabilityManager.isReachable {
            OWSActionSheets.showErrorAlert(message: NSLocalizedString("PROFILE_VIEW_NO_CONNECTION",
                                                                      comment: "Error shown when the user tries to update their profile when the app is not connected to the internet."))
            return
        }

        // Show an activity indicator to block the UI during the profile upload.
        let avatarData = self.avatarData
        let normalizedGivenName = self.normalizedGivenName
        let normalizedFamilyName = self.normalizedFamilyName

        let spinner = AnimatedProgressView()
        primaryView.addSubview(spinner)
        spinner.autoCenterInSuperviewMargins()
        spinner.startAnimating()

        firstly(on: .sharedUserInitiated) {
            OWSProfileManager.updateLocalProfilePromise(
                profileGivenName: normalizedGivenName,
                profileFamilyName: normalizedFamilyName,
                profileBio: nil,
                profileBioEmoji: nil,
                profileAvatarData: avatarData,
                visibleBadgeIds: [],
                userProfileWriter: .registration)
        }.recover { error in
            owsFailDebug("Error: \(error)")
        }.done {
            self.profileCompleted()
            UIView.animate(withDuration: 0.15) {
                spinner.alpha = 0
            } completion: { _ in
                spinner.removeFromSuperview()
            }
        }
    }

    private func profileCompleted() {
        AssertIsOnMainThread()
        Logger.verbose("")

        guard let navigationController = navigationController else { return owsFailDebug("Must have nav controller") }
        onboardingController.showNextMilestone(navigationController: navigationController)
    }

    // MARK: - Avatar

    private func setAvatarImage(_ avatarImage: UIImage?) {
        AssertIsOnMainThread()
        self.avatarData = avatarImage.map { OWSProfileManager.avatarData(forAvatarImage: $0) }

        updateAvatarView()
    }

    private func updateAvatarView() {
        if let avatarData = avatarData {
            avatarView.image = UIImage(data: avatarData)
        } else {
            let avatar = Self.avatarBuilder.avatarImageForLocalUserWithSneakyTransaction(diameterPoints: UInt(avatarSize),
                                                                                         localUserDisplayMode: .asUser)
            avatarView.image = avatar
        }
    }

    @objc
    private func didTapAvatar() {
        let currentAvatarImage: UIImage? = {
            guard let avatarData = avatarData else { return nil }
            return UIImage(data: avatarData)
        }()

        let vc = AvatarSettingsViewController(
            context: .profile,
            currentAvatarImage: currentAvatarImage
        ) { [weak self] newAvatarImage in
            self?.setAvatarImage(newAvatarImage)
        }
        presentFormSheet(OWSNavigationController(rootViewController: vc), animated: true)
    }
}

// MARK: - <UITextFieldDelegate>

extension OnboardingProfileCreationViewController: UITextFieldDelegate {

    public func textField(_ textField: UITextField,
                          shouldChangeCharactersIn range: NSRange,
                          replacementString string: String) -> Bool {

        // QuickType will append a space to any suggestions in anticipation that the user is about
        // to type more. If we're handed a multichar string with a space at the end, drop the space.
        let hasExtraTrailingSpace = string.count >= 2 && string.last == " "
        let trimmedString = hasExtraTrailingSpace ? String(string.dropLast()) : string
        let textBefore = textField.text

        let textFieldHelperPermitsChange = TextFieldHelper.textField(
            textField,
            shouldChangeCharactersInRange: range,
            replacementString: trimmedString.withoutBidiControlCharacters,
            maxByteCount: OWSUserProfile.maxNameLengthBytes
        )

        if textFieldHelperPermitsChange, hasExtraTrailingSpace {
            // TextFieldHelper will only permit the change if it hasn't already updated the text itself
            textField.text = (textField.text as NSString?)?.replacingCharacters(in: range, with: trimmedString)
        }

        if textBefore != textField.text {
            // .editingChanged actions aren't fired for programmatic updates
            textFieldDidChange(textField)
            return false
        } else {
            return textFieldHelperPermitsChange
        }
    }

    public func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField == firstTextField {
            secondTextField.becomeFirstResponder()
        } else {
            textField.resignFirstResponder()
        }
        return false
    }

    @objc
    func textFieldDidChange(_ textField: UITextField) {
        saveButton.setEnabled(isValidProfile)
    }
}
