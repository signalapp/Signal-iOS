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
        didSet { render() }
    }

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
                return StringStyle.Part.link(URL.Support.profilesAndMessageRequests)
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
            "camera-compact",
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
        result.font = .dynamicTypeSubheadlineClamped
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
        $0.addBottomStroke(color: Theme.hairlineColor, strokeWidth: .hairlineWidth)
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

    private lazy var phoneNumberDisclosureView: PhoneNumberPrivacyLabel = {
        return PhoneNumberPrivacyLabel(phoneNumberDiscoverability: state.phoneNumberDiscoverability, onTap: { [weak self] in
            guard let self else { return }
            let vc = RegistrationPhoneNumberDiscoverabilityViewController(
                state: RegistrationPhoneNumberDiscoverabilityState(
                    e164: self.state.e164,
                    phoneNumberDiscoverability: self.state.phoneNumberDiscoverability
                ),
                presenter: self
            )
            self.presentFormSheet(OWSNavigationController(rootViewController: vc), animated: true)
        })
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
        navigationItem.setHidesBackButton(true, animated: false)

        let scrollView = UIScrollView()
        view.addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: keyboardLayoutGuide.topAnchor),
        ])

        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.distribution = .fill
        stackView.spacing = 24
        stackView.setCustomSpacing(12, after: titleLabel)
        scrollView.addSubview(stackView)
        stackView.autoPinWidth(toWidthOf: scrollView)
        stackView.autoPinHeightToSuperview()

        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(explanationView)
        stackView.addArrangedSubview(avatarContainerView)
        stackView.addArrangedSubview(nameStackView)
        stackView.addArrangedSubview(phoneNumberDisclosureView)
        stackView.addArrangedSubview(UIView.vStretchingSpacer())

        scrollView.addSubview(cameraImageWrapperView)
        cameraImageWrapperView.autoPinEdge(.bottom, to: .bottom, of: avatarView)
        cameraImageWrapperView.autoPinEdge(.trailing, to: .trailing, of: avatarView)

        firstTextField.returnKeyType = .next
        secondTextField.returnKeyType = .done

        render()
    }

    private func render() {
        navigationItem.rightBarButtonItem = givenNameComponent != nil ? nextBarButton : nil

        avatarView.image = avatarData?.asImage ?? SSKEnvironment.shared.databaseStorageRef.read { transaction in
            SSKEnvironment.shared.avatarBuilderRef.defaultAvatarImageForLocalUser(
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
        textFieldStrokes.forEach { $0.backgroundColor = Theme.hairlineColor }

        phoneNumberDisclosureView.render()
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
        phoneNumberDisclosureView.phoneNumberDiscoverability = phoneNumberDiscoverability
        self.state = RegistrationProfileState(
            e164: self.state.e164,
            phoneNumberDiscoverability: phoneNumberDiscoverability
        )
        self.presentedViewController?.dismiss(animated: true)
    }
}

// MARK: - PhoneNumberPrivacyLabel

extension RegistrationProfileViewController {
    private class PhoneNumberPrivacyLabel: UIView {

        private enum Constants {
            static let iconSize: CGFloat = 24.0
            static let verticalSpacing: CGFloat = 0.0
            static let horizontalSpacing: CGFloat = 12.0
            static let layoutInsets: UIEdgeInsets = UIEdgeInsets(
                top: 8,
                leading: 0,
                bottom: 8,
                trailing: 0
            )
        }

        var phoneNumberDiscoverability: PhoneNumberDiscoverability {
            didSet { render() }
        }
        private var onTap: (() -> Void)?

        // MARK: Init

        init(phoneNumberDiscoverability: PhoneNumberDiscoverability, onTap: (() -> Void)?) {
            self.phoneNumberDiscoverability = phoneNumberDiscoverability
            self.onTap = onTap
            super.init(frame: .zero)
            initialRender()
        }

        @available(*, unavailable, message: "Use other constructor")
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        // MARK: Views

        private lazy var button: OWSFlatButton = {
            return OWSFlatButton()
        }()

        private lazy var iconView: UIImageView = {
            let iconView = UIImageView()
            iconView.contentMode = .scaleAspectFit
            return iconView
        }()

        private lazy var titleLabel: UILabel = {
            let titleLabel = UILabel()
            titleLabel.numberOfLines = 0
            titleLabel.lineBreakMode = .byWordWrapping
            return titleLabel
        }()

        private lazy var subTitleLabel: UILabel = {
            let subTitleLabel = UILabel()
            subTitleLabel.numberOfLines = 0
            subTitleLabel.lineBreakMode = .byWordWrapping
            return subTitleLabel
        }()

        private lazy var disclosureView: UIImageView = {
            let disclosureView = UIImageView()
            disclosureView.contentMode = .scaleAspectFit
            return disclosureView
        }()

        // MARK: Layout

        private func initialRender() {

            addSubview(button)
            button.autoPinEdgesToSuperviewEdges()

            let iconContainer = UIView()
            iconContainer.addSubview(iconView)

            iconView.autoPinWidthToSuperview()
            iconView.autoSetDimensions(to: CGSize(square: Constants.iconSize))
            iconView.autoVCenterInSuperview()
            iconView.autoMatch(
                .height,
                to: .height,
                of: iconContainer,
                withOffset: 0,
                relation: .lessThanOrEqual)

            let topSpacer = UIView.vStretchingSpacer()
            let bottomSpacer = UIView.vStretchingSpacer()

            let vStack = UIStackView(arrangedSubviews: [
                topSpacer,
                titleLabel,
                subTitleLabel,
                bottomSpacer
            ])
            vStack.axis = .vertical
            vStack.spacing = Constants.verticalSpacing
            topSpacer.autoMatch(.height, to: .height, of: bottomSpacer)

            let disclosureContainer = UIView()
            disclosureContainer.addSubview(disclosureView)

            disclosureView.autoPinEdgesToSuperviewEdges()
            disclosureView.autoSetDimension(.width, toSize: Constants.iconSize)

            let hStack = UIStackView(arrangedSubviews: [
                iconContainer,
                vStack,
                disclosureContainer
            ])

            hStack.axis = .horizontal
            hStack.spacing = Constants.horizontalSpacing
            hStack.isLayoutMarginsRelativeArrangement = true
            hStack.layoutMargins = Constants.layoutInsets
            hStack.isUserInteractionEnabled = false

            button.addSubview(hStack)
            hStack.autoPinEdgesToSuperviewEdges()
            button.addTarget(target: self, selector: #selector(disclosureButtonTapped))

            render()
        }

        public func render() {
            button.setBackgroundColors(upColor: Theme.backgroundColor)

            let labelIconName: String = {
                switch phoneNumberDiscoverability {
                case .everybody:
                    return "group"
                case .nobody:
                    return "lock"
                }
            }()

            titleLabel.text = OWSLocalizedString(
                "REGISTRATION_PROFILE_SETUP_FIND_MY_NUMBER_TITLE",
                comment: "During registration, users can choose who can see their phone number.")

            subTitleLabel.text = phoneNumberDiscoverability.nameForDiscoverability

            iconView.setTemplateImageName(labelIconName, tintColor: Theme.primaryIconColor)

            titleLabel.font = UIFont.dynamicTypeBodyClamped
            titleLabel.textColor = Theme.primaryTextColor

            subTitleLabel.font = UIFont.dynamicTypeCaption1Clamped
            subTitleLabel.textColor = Theme.secondaryTextAndIconColor

            disclosureView.setTemplateImage(
                UIImage(imageLiteralResourceName: "chevron-right-20"),
                tintColor: Theme.secondaryTextAndIconColor
            )
        }

        // MARK: Actions

        @objc
        func disclosureButtonTapped() {
            onTap?()
            render()
        }
    }
}

// MARK: - Data <-> UIImage conversions

private extension Data {
    var asImage: UIImage? { .init(data: self) }
}
