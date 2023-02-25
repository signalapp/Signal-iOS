//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SafariServices
import SignalMessaging

// MARK: - RegistrationProfilePresenter

protocol RegistrationProfilePresenter: AnyObject {
    func goToNextStep(givenName: String, familyName: String?, avatarData: Data?)
}

// MARK: - RegistrationProfileViewController

class RegistrationProfileViewController: OWSViewController {
    private var profilesFAQURL: URL { URL(string: "https://support.signal.org/hc/articles/360007459591")! }

    public init(presenter: RegistrationProfilePresenter) {
        self.presenter = presenter

        super.init()
    }

    @available(*, unavailable)
    public override init() {
        owsFail("This should not be called")
    }

    // MARK: Internal state

    private weak var presenter: RegistrationProfilePresenter?

    private var normalizedGivenName: String {
        return (givenNameTextField.text ?? "").ows_stripped()
    }

    private var normalizedFamilyName: String? {
        return (familyNameTextField.text ?? "").ows_stripped().nilIfEmpty
    }

    private var avatarData: Data? {
        didSet { render() }
    }

    private var canSubmit: Bool { !normalizedGivenName.isEmpty }

    // MARK: Rendering

    private lazy var nextBarButton = UIBarButtonItem(
        title: CommonStrings.nextButton,
        style: .done,
        target: self,
        action: #selector(didTapNext),
        accessibilityIdentifier: "registration.profile.nextButton"
    )

    private lazy var titleLabel: UILabel = {
        let result = UILabel.titleLabelForRegistration(text: OWSLocalizedString(
            "REGISTRATION_PROFILE_SETUP_TITLE",
            comment: "During registration, users set up their profile. This is the title on the screen where this is done."
        ))
        result.accessibilityIdentifier = "registration.profile.titleLabel"
        return result
    }()

    private lazy var explanationView: LinkingTextView = {
        let result = LinkingTextView()
        result.attributedText = .composed(of: [
            OWSLocalizedString(
                "REGISTRATION_PROFILE_SETUP_SUBTITLE",
                comment: "During registration, users set up their profile. This is the subtitle on the screen where this is done. It tells users about the privacy of their profile. A \"learn more\" link will be added to the end of this string."
            ),
            " ",
            CommonStrings.learnMore.styled(with: {
                // We'd like a link that doesn't go anywhere, because we'd like to handle the
                // tapping ourselves. We use a "fake" URL because BonMot needs one.
                return StringStyle.Part.link(profilesFAQURL)
            }())
        ])
        result.font = .fontForRegistrationExplanationLabel
        result.textAlignment = .center
        result.delegate = self
        return result
    }()

    private lazy var avatarTapGestureRecognizer = UITapGestureRecognizer(
        target: self,
        action: #selector(didTapAvatar)
    )

    private let avatarSize: CGFloat = 64
    private lazy var avatarView: AvatarImageView = {
        let result = AvatarImageView()
        result.autoSetDimensions(to: .square(avatarSize))
        result.accessibilityIdentifier = "registration.profile.avatarView"

        result.addGestureRecognizer(avatarTapGestureRecognizer)
        result.isUserInteractionEnabled = true
        return result
    }()

    private lazy var avatarContainerView: UIView = {
        let result = UIView()
        result.addSubview(avatarView)
        result.autoSetDimension(.height, toSize: avatarSize)
        avatarView.autoCenterInSuperview()
        return result
    }()

    private lazy var cameraImageView: UIImageView = {
        let result = UIImageView.withTemplateImageName(
            "camera-outline-24",
            // This color will be swiftly updated during renders.
            tintColor: Theme.secondaryTextAndIconColor
        )
        result.autoSetDimensions(to: CGSize(square: 16))
        return result
    }()

    private lazy var cameraImageWrapperView: UIView = {
        let result = UIView()
        let size = CGSize(square: 28)
        result.addSubview(cameraImageView)
        result.layer.cornerRadius = size.largerAxis / 2
        cameraImageView.autoCenterInSuperview()
        result.autoSetDimensions(to: size)
        result.addGestureRecognizer(avatarTapGestureRecognizer)
        result.isUserInteractionEnabled = true
        return result
    }()

    private func textField(
        placeholder: String,
        textContentType: UITextContentType,
        accessibilityIdentifierSuffix: String
    ) -> UITextField {
        let result = OWSTextField()
        result.font = .ows_dynamicTypeSubheadlineClamped
        result.adjustsFontForContentSizeCategory = true
        result.textAlignment = .natural
        result.autocorrectionType = .no
        result.spellCheckingType = .no

        result.placeholder = placeholder
        result.textContentType = textContentType
        result.accessibilityIdentifier = "registration.profile.\(accessibilityIdentifierSuffix)"

        result.delegate = self
        result.addTarget(self, action: #selector(didTextFieldChange), for: .editingChanged)

        result.autoSetDimension(.height, toSize: 50, relation: .greaterThanOrEqual)

        return result
    }

    private lazy var givenNameTextField: UITextField = textField(
        placeholder: OWSLocalizedString(
            "REGISTRATION_PROFILE_SETUP_GIVEN_NAME_FIELD_PLACEHOLDER",
            comment: "During registration, users set up their profile. Users input a given name. This is the placeholder for that field."
        ),
        textContentType: .givenName,
        accessibilityIdentifierSuffix: "givenName"
    )

    private lazy var familyNameTextField: UITextField = textField(
        placeholder: OWSLocalizedString(
            "REGISTRATION_PROFILE_SETUP_FAMILY_NAME_FIELD_PLACEHOLDER",
            comment: "During registration, users set up their profile. Users input a family name. This is the placeholder for that field."
        ),
        textContentType: .familyName,
        accessibilityIdentifierSuffix: "familyName"
    )

    private lazy var textFieldStrokes: [UIView] = [givenNameTextField, familyNameTextField].map {
        // This color will be swiftly updated during renders.
        $0.addBottomStroke(color: Theme.cellSeparatorColor, strokeWidth: CGHairlineWidth())
    }

    private enum NameOrder {
        case familyNameFirst
        case givenNameFirst
    }
    private var nameOrder: NameOrder { Locale.current.isCJKV ? .familyNameFirst : .givenNameFirst }

    private lazy var firstTextField: UITextField = {
        switch nameOrder {
        case .givenNameFirst: return givenNameTextField
        case .familyNameFirst: return familyNameTextField
        }
    }()

    private lazy var secondTextField: UITextField = {
        switch nameOrder {
        case .givenNameFirst: return familyNameTextField
        case .familyNameFirst: return givenNameTextField
        }
    }()

    private lazy var nameStackView: UIView = {
        let result = UIStackView(arrangedSubviews: [firstTextField, secondTextField])
        result.axis = .vertical
        result.distribution = .fillEqually
        return result
    }()

    public override func viewDidLoad() {
        super.viewDidLoad()
        initialRender()
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if !UIDevice.current.isIPhone5OrShorter {
            // Small devices may obscure parts of the UI behind the keyboard, especially with larger
            // font sizes.
            firstTextField.becomeFirstResponder()
        }
    }

    public override func themeDidChange() {
        super.themeDidChange()
        render()
    }

    private func initialRender() {
        let scrollView = UIScrollView()
        view.addSubview(scrollView)
        scrollView.autoPinWidthToSuperviewMargins()
        scrollView.autoPinEdge(toSuperviewEdge: .top)
        scrollView.autoPinEdge(.bottom, to: .bottom, of: keyboardLayoutGuideViewSafeArea)

        let stackView = UIStackView(arrangedSubviews: [
            titleLabel,
            explanationView,
            avatarContainerView,
            nameStackView,
            UIView.vStretchingSpacer()
        ])
        stackView.axis = .vertical
        stackView.distribution = .fill
        stackView.spacing = 24
        stackView.setCustomSpacing(12, after: titleLabel)
        scrollView.addSubview(stackView)
        stackView.autoPinWidth(toWidthOf: scrollView)
        stackView.autoPinHeightToSuperview()

        scrollView.addSubview(cameraImageWrapperView)
        cameraImageWrapperView.autoPinEdge(.bottom, to: .bottom, of: avatarView)
        cameraImageWrapperView.autoPinEdge(.trailing, to: .trailing, of: avatarView)

        firstTextField.returnKeyType = .next
        secondTextField.returnKeyType = .done

        render()
    }

    private func render() {
        navigationItem.rightBarButtonItem = canSubmit ? nextBarButton : nil

        avatarView.image = avatarData?.asImage ?? Self.databaseStorage.read { transaction in
            Self.avatarBuilder.defaultAvatarImageForLocalUser(
                diameterPoints: UInt(avatarSize),
                transaction: transaction
            )
        }

        view.backgroundColor = Theme.backgroundColor
        nextBarButton.tintColor = Theme.accentBlueColor
        titleLabel.textColor = .colorForRegistrationTitleLabel
        explanationView.textColor = .colorForRegistrationExplanationLabel
        explanationView.linkTextAttributes = [
            .foregroundColor: Theme.accentBlueColor,
            .underlineColor: UIColor.clear
        ]
        cameraImageView.tintColor = Theme.secondaryTextAndIconColor
        cameraImageWrapperView.backgroundColor = Theme.backgroundColor
        [givenNameTextField, familyNameTextField].forEach { $0.textColor = Theme.primaryTextColor }
        textFieldStrokes.forEach { $0.backgroundColor = Theme.cellSeparatorColor }
    }

    // MARK: Events

    @objc
    private func didTextFieldChange() {
        render()
    }

    @objc
    private func didTapAvatar() {
        Logger.info("")

        let vc = AvatarSettingsViewController(
            context: .profile,
            currentAvatarImage: avatarData?.asImage
        ) { [weak self] newAvatarImage in
            guard let self else { return }
            self.avatarData = newAvatarImage?.asData
        }
        presentFormSheet(OWSNavigationController(rootViewController: vc), animated: true)
    }

    @objc
    private func didTapNext() {
        Logger.info("")

        guard canSubmit else { return }

        goToNextStep()
    }

    private func goToNextStep() {
        Logger.info("")

        presenter?.goToNextStep(
            givenName: normalizedGivenName,
            familyName: normalizedFamilyName,
            avatarData: avatarData
        )
    }
}

// MARK: - UITextViewDelegate

extension RegistrationProfileViewController: UITextViewDelegate {
    func textView(
        _ textView: UITextView,
        shouldInteractWith URL: URL,
        in characterRange: NSRange,
        interaction: UITextItemInteraction
    ) -> Bool {
        if textView == explanationView {
            showLearnMoreUi()
        }
        return false
    }

    private func showLearnMoreUi() {
        let actionSheet = ActionSheetController(
            title: OWSLocalizedString(
                "REGISTRATION_PROFILE_SETUP_MORE_INFO_TITLE",
                comment: "During registration, users set up their profile. They can learn more about the privacy of their profile by clicking a \"learn more\" button. This is the title on a sheet that appears when they do that."
            ),
            message: OWSLocalizedString(
                "REGISTRATION_PROFILE_SETUP_MORE_INFO_DETAILS",
                comment: "During registration, users set up their profile. They can learn more about the privacy of their profile by clicking a \"learn more\" button. This is the message on a sheet that appears when they do that."
            )
        )

        actionSheet.addAction(.init(title: CommonStrings.learnMore) { [weak self] _ in
            guard let self else { return }
            self.present(SFSafariViewController(url: self.profilesFAQURL), animated: true)
        })

        actionSheet.addAction(.init(title: CommonStrings.okayButton, style: .cancel))

        presentActionSheet(actionSheet)
    }
}

// MARK: - UITextFieldDelegate

extension RegistrationProfileViewController: UITextFieldDelegate {
    public func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        switch textField {
        case firstTextField:
            secondTextField.becomeFirstResponder()
        case secondTextField:
            if canSubmit { goToNextStep() }
        default:
            owsFailBeta("Got a \"return\" event for an unexpected text field")
        }
        return false
    }
}

// MARK: - Data <-> UIImage conversions

private extension Data {
    var asImage: UIImage? { .init(data: self) }
}

private extension UIImage {
    var asData: Data { OWSProfileManager.avatarData(forAvatarImage: self) }
}
