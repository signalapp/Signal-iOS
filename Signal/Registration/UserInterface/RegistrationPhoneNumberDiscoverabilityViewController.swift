//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

protocol RegistrationPhoneNumberDiscoverabilityPresenter: AnyObject {
    func setPhoneNumberDiscoverability(_ phoneNumberDiscoverability: PhoneNumberDiscoverability)
    var presentedAsModal: Bool { get }
}

public struct RegistrationPhoneNumberDiscoverabilityState: Equatable {
    let e164: E164
    let phoneNumberDiscoverability: PhoneNumberDiscoverability
}

class RegistrationPhoneNumberDiscoverabilityViewController: OWSViewController {
    private let state: RegistrationPhoneNumberDiscoverabilityState
    private weak var presenter: RegistrationPhoneNumberDiscoverabilityPresenter?

    init(
        state: RegistrationPhoneNumberDiscoverabilityState,
        presenter: RegistrationPhoneNumberDiscoverabilityPresenter,
    ) {
        self.state = state
        self.presenter = presenter
        self.phoneNumberDiscoverability = state.phoneNumberDiscoverability

        super.init()

        navigationItem.hidesBackButton = true
    }

    @available(*, unavailable)
    override init() {
        owsFail("This should not be called")
    }

    // MARK: State

    private var phoneNumberDiscoverability: PhoneNumberDiscoverability {
        didSet { update() }
    }

    // MARK: UI

    private lazy var everybodyButton: UIButton = createButtonForDiscoverability(.everybody)
    private lazy var nobodyButton: UIButton = createButtonForDiscoverability(.nobody)

    private func createButtonForDiscoverability(_ phoneNumberDiscoverability: PhoneNumberDiscoverability) -> UIButton {
        let button = PrivacySettingButton(phoneNumberDiscoverability: phoneNumberDiscoverability)
        button.addAction(
            UIAction { [weak self] _ in
                self?.phoneNumberDiscoverability = phoneNumberDiscoverability
            },
            for: .primaryActionTriggered,
        )
        return button
    }

    private lazy var selectionDescriptionLabel: UILabel = {
        let label = UILabel.explanationLabelForRegistration(text: "")
        label.font = .dynamicTypeFootnoteClamped
        return label
    }()

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .Signal.background

        navigationItem.setHidesBackButton(true, animated: false)
        if !(presenter?.presentedAsModal ?? true) {
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                title: CommonStrings.nextButton,
                style: .done,
                target: self,
                action: #selector(didTapSave),
                accessibilityIdentifier: "registration.phoneNumberDiscoverability.nextButton",
            )
        }

        let titleLabel = UILabel.titleLabelForRegistration(text: OWSLocalizedString(
            "ONBOARDING_PHONE_NUMBER_DISCOVERABILITY_TITLE",
            comment: "Title of the 'onboarding phone number discoverability' view.",
        ))
        titleLabel.accessibilityIdentifier = "registration.phoneNumberDiscoverability.titleLabel"

        let formattedPhoneNumber = state.e164.stringValue
        let explanationTextFormat = OWSLocalizedString(
            "ONBOARDING_PHONE_NUMBER_DISCOVERABILITY_EXPLANATION_FORMAT",
            comment: "Explanation of the 'onboarding phone number discoverability' view. Embeds {user phone number}",
        )
        let subtitleLabel = UILabel.explanationLabelForRegistration(
            text: String(format: explanationTextFormat, formattedPhoneNumber),
        )
        subtitleLabel.accessibilityIdentifier = "registration.phoneNumberDiscoverability.explanationLabel"

        let stackView = addStaticContentStackView(arrangedSubviews: [
            titleLabel,
            subtitleLabel,
            everybodyButton,
            nobodyButton,
            selectionDescriptionLabel,
            .vStretchingSpacer(),
        ])
        if presenter?.presentedAsModal ?? false {
            let continueButton = UIButton(
                configuration: .largePrimary(title: CommonStrings.continueButton),
                primaryAction: UIAction { [weak self] _ in
                    self?.didTapSave()
                },
            )
            continueButton.accessibilityIdentifier = "registration.phoneNumberDiscoverability.saveButton"

            stackView.addArrangedSubview(continueButton.enclosedInVerticalStackView(isFullWidthButton: true))
        }
        stackView.spacing = 16
        stackView.setCustomSpacing(24, after: subtitleLabel)

        update()
    }

    private func update() {
        everybodyButton.isSelected = phoneNumberDiscoverability == .everybody
        nobodyButton.isSelected = phoneNumberDiscoverability == .nobody
        selectionDescriptionLabel.text = phoneNumberDiscoverability.descriptionForDiscoverability
    }

    // MARK: Events

    @objc
    private func didTapSave() {
        presenter?.setPhoneNumberDiscoverability(phoneNumberDiscoverability)
    }
}

// MARK: - Privacy setting buttons

private extension RegistrationPhoneNumberDiscoverabilityViewController {

    private class PrivacySettingButton: UIButton {
        private lazy var contentView = PrivacySettingButtonContentView(
            configuration: .init(phoneNumberDiscoverability: phoneNumberDiscoverability),
        )

        var phoneNumberDiscoverability: PhoneNumberDiscoverability {
            didSet {
                contentView.configuration = PrivacySettingButtonContentConfiguration(
                    phoneNumberDiscoverability: phoneNumberDiscoverability,
                )
            }
        }

        override var isSelected: Bool {
            didSet {
                contentView.configuration = PrivacySettingButtonContentConfiguration(
                    phoneNumberDiscoverability: phoneNumberDiscoverability,
                    isSelected: isSelected,
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
                contentView.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        // MARK: Accessibility

        override var accessibilityLabel: String? {
            get { phoneNumberDiscoverability.nameForDiscoverability }
            set { super.accessibilityLabel = newValue }
        }

        override var accessibilityHint: String? {
            get { phoneNumberDiscoverability.descriptionForDiscoverability }
            set { super.accessibilityHint = newValue }
        }

    }

    private struct PrivacySettingButtonContentConfiguration: UIContentConfiguration {
        var phoneNumberDiscoverability: PhoneNumberDiscoverability
        var isSelected = false

        func makeContentView() -> UIView & UIContentView {
            PrivacySettingButtonContentView(configuration: self)
        }

        func updated(for state: UIConfigurationState) -> PrivacySettingButtonContentConfiguration {
            // Looks the same.
            self
        }
    }

    private class PrivacySettingButtonContentView: UIView, UIContentView {

        private var _configuration: PrivacySettingButtonContentConfiguration!

        var configuration: UIContentConfiguration {
            get { _configuration }
            set {
                guard let configuration = newValue as? PrivacySettingButtonContentConfiguration else { return }
                _configuration = configuration
                apply(configuration)
            }
        }

        init(configuration: PrivacySettingButtonContentConfiguration) {
            super.init(frame: .zero)

            isUserInteractionEnabled = false
            layoutMargins = .init(hMargin: 8, vMargin: 8)

            let hStack = UIStackView(arrangedSubviews: [titleLabel, checkmark])
            hStack.axis = .horizontal
            hStack.alignment = .center
            hStack.spacing = 12

            addSubview(hStack)
            hStack.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                hStack.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor),
                hStack.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
                hStack.bottomAnchor.constraint(equalTo: layoutMarginsGuide.bottomAnchor),
                hStack.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),

                titleLabel.heightAnchor.constraint(greaterThanOrEqualTo: checkmark.heightAnchor),
                heightAnchor.constraint(greaterThanOrEqualToConstant: 48),
            ])

            addBottomStroke(color: .Signal.opaqueSeparator, strokeWidth: .hairlineWidth)

            apply(configuration)
        }

        @available(*, unavailable, message: "Use other constructor")
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        private lazy var checkmark: UIView = {
            let iconView = UIImageView()
            iconView.contentMode = .scaleAspectFit
            iconView.translatesAutoresizingMaskIntoConstraints = false
            iconView.widthAnchor.constraint(equalToConstant: 24).isActive = true
            iconView.setTemplateImage(Theme.iconImage(.checkmark), tintColor: .Signal.label)
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
                comment: "During registration, users can choose who can see their phone number.",
            )
            return titleLabel
        }()

        private func apply(_ configuration: PrivacySettingButtonContentConfiguration) {
            titleLabel.text = configuration.phoneNumberDiscoverability.nameForDiscoverability
            checkmark.isHidden = !configuration.isSelected
        }
    }

}
