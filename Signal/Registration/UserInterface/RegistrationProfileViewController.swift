//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SafariServices
import SignalServiceKit
import SignalUI

// MARK: - RegistrationProfileState

public struct RegistrationProfileState: Equatable {
    let e164: E164
    let phoneNumberDiscoverability: PhoneNumberDiscoverability
}

// MARK: - RegistrationProfilePresenter

protocol RegistrationProfilePresenter: AnyObject {
    func goToNextStep(
        givenName: OWSUserProfile.NameComponent,
        familyName: OWSUserProfile.NameComponent?,
        avatarData: Data?,
        phoneNumberDiscoverability: PhoneNumberDiscoverability
    )
}

// MARK: - RegistrationProfileViewController

class RegistrationProfileViewController: OWSViewController {
    var state: RegistrationProfileState

    public init(
        state: RegistrationProfileState,
        presenter: RegistrationProfilePresenter
    ) {
        self.presenter = presenter
        self.state = state

        super.init()

        navigationItem.hidesBackButton = true
    }

    @available(*, unavailable)
    public override init() {
        owsFail("This should not be called")
    }

    // MARK: Internal state

    private weak var presenter: RegistrationProfilePresenter?

    private var givenNameComponent: OWSUserProfile.NameComponent? {
        return OWSUserProfile.NameComponent(truncating: givenNameTextField.text ?? "")
    }

    private var familyNameComponent: OWSUserProfile.NameComponent? {
        return OWSUserProfile.NameComponent(truncating: familyNameTextField.text ?? "")
    }

    private var avatarData: Data? {
        didSet { updateUI() }
    }

    // MARK: UI

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
                return StringStyle.Part.link(URL.Support.profilesAndMessageRequests)
            }())
        ])
        result.textColor = .Signal.secondaryLabel
        result.font = .dynamicTypeBody
        result.textAlignment = .center
        result.delegate = self
        return result
    }()

    private let avatarSize: CGFloat = 64
    private lazy var avatarView: AvatarImageView = {
        let result = AvatarImageView()
        result.translatesAutoresizingMaskIntoConstraints = false
        result.addConstraints([
            result.widthAnchor.constraint(equalToConstant: avatarSize),
            result.heightAnchor.constraint(equalToConstant: avatarSize),
        ])
        result.accessibilityIdentifier = "registration.profile.avatarView"
        result.addGestureRecognizer(UITapGestureRecognizer(
            target: self,
            action: #selector(didTapAvatar)
        ))
        result.isUserInteractionEnabled = true
        return result
    }()

    private lazy var cameraIconView: UIView = {
        let iconSize: CGFloat = 16
        let viewSize: CGFloat = 28

        let view = UIView()
        view.backgroundColor = .Signal.background
        view.layer.cornerRadius = viewSize / 2
        view.addGestureRecognizer(UITapGestureRecognizer(
            target: self,
            action: #selector(didTapAvatar)
        ))
        view.isUserInteractionEnabled = true

        let cameraImageIcon =  UIImageView.withTemplateImageName(
            "camera-compact",
            // This color will be swiftly updated during renders.
            tintColor: .Signal.secondaryLabel
        )
        view.addSubview(cameraImageIcon)

        view.translatesAutoresizingMaskIntoConstraints = false
        cameraImageIcon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            cameraImageIcon.widthAnchor.constraint(equalToConstant: iconSize),
            cameraImageIcon.heightAnchor.constraint(equalToConstant: iconSize),
            cameraImageIcon.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            cameraImageIcon.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            view.widthAnchor.constraint(equalToConstant: viewSize),
            view.heightAnchor.constraint(equalToConstant: viewSize),
        ])

        return view
    }()

    private func textField(
        placeholder: String,
        textContentType: UITextContentType,
        accessibilityIdentifierSuffix: String
    ) -> UITextField {
        let result = OWSTextField()
        result.font = .dynamicTypeBodyClamped
        result.textColor = .Signal.label
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
        result.addBottomStroke(color: .Signal.opaqueSeparator, strokeWidth: .hairlineWidth)
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

    private lazy var phoneNumberPrivacyButton: PhoneNumberPrivacyButton = {
        let button = PhoneNumberPrivacyButton(phoneNumberDiscoverability: state.phoneNumberDiscoverability)
        button.addAction(
            UIAction { [weak self] _ in
                guard let self else { return }
                let vc = RegistrationPhoneNumberDiscoverabilityViewController(
                    state: RegistrationPhoneNumberDiscoverabilityState(
                        e164: self.state.e164,
                        phoneNumberDiscoverability: self.state.phoneNumberDiscoverability
                    ),
                    presenter: self
                )
                self.presentFormSheet(OWSNavigationController(rootViewController: vc), animated: true)
            },
            for: .primaryActionTriggered
        )
        return button
    }()

    public override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .Signal.background

        navigationItem.rightBarButtonItem?.tintColor = .Signal.accent
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: CommonStrings.nextButton,
            style: .done,
            target: self,
            action: #selector(didTapNext),
            accessibilityIdentifier: "registration.profile.nextButton"
        )

        let scrollView = UIScrollView()
        scrollView.preservesSuperviewLayoutMargins = true
        view.addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: keyboardLayoutGuide.topAnchor),
        ])

        let avatarContainerView = UIView.container()
        avatarContainerView.addSubview(avatarView)
        avatarContainerView.addSubview(cameraIconView)
        avatarView.translatesAutoresizingMaskIntoConstraints = false
        cameraIconView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            avatarView.topAnchor.constraint(equalTo: avatarContainerView.topAnchor),
            avatarView.centerXAnchor.constraint(equalTo: avatarContainerView.centerXAnchor),
            avatarView.bottomAnchor.constraint(equalTo: avatarContainerView.bottomAnchor),

            cameraIconView.bottomAnchor.constraint(equalTo: avatarView.bottomAnchor),
            cameraIconView.trailingAnchor.constraint(equalTo: avatarView.trailingAnchor),
        ])

        let stackView = UIStackView(arrangedSubviews: [
            titleLabel,
            explanationView,
            avatarContainerView,
            nameStackView,
            phoneNumberPrivacyButton,
            UIView.vStretchingSpacer(),
        ])
        stackView.axis = .vertical
        stackView.distribution = .fill
        stackView.spacing = 24
        stackView.setCustomSpacing(12, after: titleLabel)
        stackView.preservesSuperviewLayoutMargins = true
        stackView.isLayoutMarginsRelativeArrangement = true

        scrollView.addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stackView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            stackView.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.frameLayoutGuide.heightAnchor),
        ])

        firstTextField.returnKeyType = .next
        secondTextField.returnKeyType = .done

        updateUI()
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if !UIDevice.current.isIPhone5OrShorter {
            // Small devices may obscure parts of the UI behind the keyboard, especially with larger
            // font sizes.
            firstTextField.becomeFirstResponder()
        }
    }

    private func updateUI() {
        navigationItem.rightBarButtonItem?.isEnabled = givenNameComponent != nil

        avatarView.image = avatarData?.asImage ?? SSKEnvironment.shared.databaseStorageRef.read { transaction in
            SSKEnvironment.shared.avatarBuilderRef.defaultAvatarImageForLocalUser(
                diameterPoints: UInt(avatarSize),
                transaction: transaction
            )
        }
    }

    // MARK: Events

    @objc
    private func didTextFieldChange() {
        updateUI()
    }

    @objc
    private func didTapAvatar() {
        Logger.info("")

        let vc = AvatarSettingsViewController(
            context: .profile,
            currentAvatarImage: avatarData?.asImage
        ) { [weak self] newAvatarImage in
            guard let self else { return }
            if let newAvatarImage {
                self.avatarData = OWSProfileManager.avatarData(avatarImage: newAvatarImage)
            } else {
                self.avatarData = nil
            }
        }
        presentFormSheet(OWSNavigationController(rootViewController: vc), animated: true)
    }

    @objc
    private func didTapNext() {
        Logger.info("")
        goToNextStepIfPossible()
    }

    private func goToNextStepIfPossible() {
        Logger.info("")

        guard let givenNameComponent else {
            // This can happen if you try to advance via the keyboard.
            return
        }

        presenter?.goToNextStep(
            givenName: givenNameComponent,
            familyName: familyNameComponent,
            avatarData: avatarData,
            phoneNumberDiscoverability: state.phoneNumberDiscoverability
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
            showLearnMoreUI()
        }
        return false
    }

    private func showLearnMoreUI() {
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
            self.present(SFSafariViewController(url: URL.Support.profilesAndMessageRequests), animated: true)
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
            goToNextStepIfPossible()
        default:
            owsFailBeta("Got a \"return\" event for an unexpected text field")
        }
        return false
    }
}

// MARK: - RegistrationPhoneNumberDiscoverabilityPresenter

extension RegistrationProfileViewController: RegistrationPhoneNumberDiscoverabilityPresenter {

    var presentedAsModal: Bool { return true }

    func setPhoneNumberDiscoverability(_ phoneNumberDiscoverability: PhoneNumberDiscoverability) {
        phoneNumberPrivacyButton.phoneNumberDiscoverability = phoneNumberDiscoverability
        self.state = RegistrationProfileState(
            e164: self.state.e164,
            phoneNumberDiscoverability: phoneNumberDiscoverability
        )
        self.presentedViewController?.dismiss(animated: true)
    }
}

// MARK: - Phone number privacy button

extension RegistrationProfileViewController {

    private class PhoneNumberPrivacyButton: UIButton {

        private lazy var contentView = PhoneNumberPrivacyButtonContentView(
            configuration: .init(phoneNumberDiscoverability: phoneNumberDiscoverability)
        )

        var phoneNumberDiscoverability: PhoneNumberDiscoverability {
            didSet {
                contentView.configuration = PhoneNumberPrivacyButtonContentConfiguration(
                    phoneNumberDiscoverability: phoneNumberDiscoverability
                )
            }
        }

        init(phoneNumberDiscoverability: PhoneNumberDiscoverability) {
            self.phoneNumberDiscoverability = phoneNumberDiscoverability

            super.init(frame: .zero)

            configuration = .filled()
            configuration?.baseBackgroundColor = .Signal.background

            addSubview(contentView)
            contentView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
                contentView.topAnchor.constraint(equalTo: topAnchor),
                contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
                contentView.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }

    private struct PhoneNumberPrivacyButtonContentConfiguration: UIContentConfiguration {
        var phoneNumberDiscoverability: PhoneNumberDiscoverability

        func makeContentView() -> UIView & UIContentView {
            PhoneNumberPrivacyButtonContentView(configuration: self)
        }

        func updated(for state: UIConfigurationState) -> PhoneNumberPrivacyButtonContentConfiguration {
            // Looks the same.
            self
        }
    }

    private class PhoneNumberPrivacyButtonContentView: UIView, UIContentView {

        private var _configuration: PhoneNumberPrivacyButtonContentConfiguration!

        var configuration: UIContentConfiguration {
            get { _configuration }
            set {
                guard let configuration = newValue as? PhoneNumberPrivacyButtonContentConfiguration else { return }
                _configuration = configuration
                apply(configuration)
            }
        }

        init(configuration: PhoneNumberPrivacyButtonContentConfiguration) {
            super.init(frame: .zero)

            isUserInteractionEnabled = false
            layoutMargins = .init(hMargin: 0, vMargin: 8)

            let vStack = UIStackView(arrangedSubviews: [ titleLabel, subTitleLabel ])
            vStack.axis = .vertical
            vStack.spacing = 4

            let disclosureView = UIImageView()
            disclosureView.contentMode = .scaleAspectFit
            disclosureView.setTemplateImage(
                UIImage(imageLiteralResourceName: "chevron-right-20"),
                tintColor: .Signal.secondaryLabel
            )
            disclosureView.translatesAutoresizingMaskIntoConstraints = false
            disclosureView.widthAnchor.constraint(equalToConstant: 24).isActive = true

            let hStack = UIStackView(arrangedSubviews: [
                iconView,
                vStack,
                disclosureView
            ])
            hStack.axis = .horizontal
            hStack.spacing = 12
            hStack.alignment = .center

            addSubview(hStack)
            hStack.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                hStack.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor),
                hStack.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
                hStack.bottomAnchor.constraint(equalTo: layoutMarginsGuide.bottomAnchor),
                hStack.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            ])

            apply(configuration)
       }

        @available(*, unavailable, message: "Use other constructor")
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        private lazy var iconView: UIImageView = {
            let iconView = UIImageView()
            iconView.contentMode = .scaleAspectFit
            iconView.translatesAutoresizingMaskIntoConstraints = false
            iconView.widthAnchor.constraint(equalToConstant: 24).isActive = true
            return iconView
        }()

        private lazy var titleLabel: UILabel = {
            let titleLabel = UILabel()
            titleLabel.font = .dynamicTypeBodyClamped
            titleLabel.textColor = .Signal.label
            titleLabel.numberOfLines = 0
            titleLabel.lineBreakMode = .byWordWrapping
            titleLabel.text = OWSLocalizedString(
                "REGISTRATION_PROFILE_SETUP_FIND_MY_NUMBER_TITLE",
                comment: "During registration, users can choose who can see their phone number."
            )
            return titleLabel
        }()

        private lazy var subTitleLabel: UILabel = {
            let subTitleLabel = UILabel()
            subTitleLabel.font = .dynamicTypeSubheadlineClamped
            subTitleLabel.textColor = .Signal.secondaryLabel
            subTitleLabel.numberOfLines = 0
            subTitleLabel.lineBreakMode = .byWordWrapping
            return subTitleLabel
        }()

        private func apply(_ configuration: PhoneNumberPrivacyButtonContentConfiguration) {
            let discoverability = configuration.phoneNumberDiscoverability

            subTitleLabel.text = discoverability.nameForDiscoverability

            let labelIconName: String = {
                switch discoverability {
                case .everybody:
                    return "group"
                case .nobody:
                    return "lock"
                }
            }()
            iconView.setTemplateImageName(labelIconName, tintColor: Theme.primaryIconColor)
        }
    }
}

// MARK: - Data <-> UIImage conversions

private extension Data {
    var asImage: UIImage? { .init(data: self) }
}
