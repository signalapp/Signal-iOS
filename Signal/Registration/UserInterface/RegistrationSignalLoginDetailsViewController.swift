//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalServiceKit
import SignalUI

// MARK: - RegistrationSignalLoginDetailsPresenter

protocol RegistrationSignalLoginDetailsPresenter: AnyObject {
    // TODO[#less]: Add callbacks to move to 'manuallly save login' step, or to continue with registration
}

// MARK: - RegistrationSignalLoginDetailsState

public struct RegistrationSignalLoginDetailsState: Equatable {
    let aci: Aci
    let aep: SignalServiceKit.AccountEntropyPool
}

// MARK: - RegistrationSignalLoginDetailsViewController

class RegistrationSignalLoginDetailsViewController: OWSViewController {

    private enum Constants {
        static let stackEdgeInsets = NSDirectionalEdgeInsets(top: 0, leading: 18, bottom: 10, trailing: 18)
        static let sectionSpacing: CGFloat = 8
        static let bodyLabelMargins: CGFloat = 20

        static let cardAspectRatio: CGFloat = 220 / 360
        static let cardCornerRadius: CGFloat = 22
        static let cardContentInsets = NSDirectionalEdgeInsets(top: 60, leading: 24, bottom: 20, trailing: 24)
        static let cardFieldSpacing: CGFloat = 4
        static let maskedValueVisibleCharacterCount = 4
    }

    private let state: RegistrationSignalLoginDetailsState
    private weak var presenter: RegistrationSignalLoginDetailsPresenter?

    init(
        state: RegistrationSignalLoginDetailsState,
        presenter: RegistrationSignalLoginDetailsPresenter,
    ) {
        self.state = state
        self.presenter = presenter

        super.init()
        navigationItem.hidesBackButton = true
    }

    @available(*, unavailable)
    override init() {
        owsFail("This should not be called")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .Signal.background

        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
        ])

        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.directionalLayoutMargins = Constants.stackEdgeInsets
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.spacing = Constants.sectionSpacing
        scrollView.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stackView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            stackView.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.frameLayoutGuide.heightAnchor),
        ])

        // Keys image

        let titleImageView = UIImageView(image: .signalLoginKeysCheckmark)
        titleImageView.translatesAutoresizingMaskIntoConstraints = false
        titleImageView.contentMode = .center
        stackView.addArrangedSubview(titleImageView)
        stackView.setCustomSpacing(16, after: titleImageView)

        // Title

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = UIFont.dynamicTypeTitle2.semibold()
        titleLabel.textColor = .Signal.label
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        titleLabel.text = OWSLocalizedString(
            "REGISTRATION_SIGNAL_LOGIN_DETAILS_TITLE",
            comment: "Title text for the 'Signal Login details' screen shown after purchasing a Signal Login.",
        )
        stackView.addArrangedSubview(titleLabel)

        // Body

        let bodyLabel = UILabel()
        bodyLabel.translatesAutoresizingMaskIntoConstraints = false
        bodyLabel.font = UIFont.dynamicTypeSubheadlineClamped
        bodyLabel.textColor = .Signal.secondaryLabel
        bodyLabel.numberOfLines = 0
        bodyLabel.textAlignment = .center
        bodyLabel.text = OWSLocalizedString(
            "REGISTRATION_SIGNAL_LOGIN_DETAILS_BODY",
            comment: "Description for the 'Signal Login details' screen shown after purchasing a Signal Login.",
        )

        let bodyLabelContainer = UIView.transparentContainer()
        bodyLabelContainer.translatesAutoresizingMaskIntoConstraints = false
        bodyLabelContainer.addSubview(bodyLabel)
        stackView.addArrangedSubview(bodyLabelContainer)
        stackView.setCustomSpacing(24, after: bodyLabelContainer)
        NSLayoutConstraint.activate([
            bodyLabel.topAnchor.constraint(equalTo: bodyLabelContainer.topAnchor),
            bodyLabel.bottomAnchor.constraint(equalTo: bodyLabelContainer.bottomAnchor),
            bodyLabel.centerXAnchor.constraint(equalTo: bodyLabelContainer.centerXAnchor),
            bodyLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: bodyLabelContainer.leadingAnchor,
                constant: Constants.bodyLabelMargins,
            ),
            bodyLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: bodyLabelContainer.trailingAnchor,
                constant: -Constants.bodyLabelMargins,
            ),
        ])

        // Signal Login card

        stackView.addArrangedSubview(buildCardView())

        // Spacer

        let spacer = SpacerView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(UILayoutPriority(1), for: .vertical)
        spacer.setContentCompressionResistancePriority(UILayoutPriority(1), for: .vertical)
        stackView.addArrangedSubview(spacer)

        // Buttons

        let saveToPasswordManagerButton = UIButton(
            configuration: .largePrimary(title: OWSLocalizedString(
                "REGISTRATION_SIGNAL_LOGIN_DETAILS_SAVE_TO_PASSWORD_MANAGER_BUTTON",
                comment: "Button on the 'Signal Login details' screen to save the Signal Login to a password manager.",
            )),
            primaryAction: UIAction { [weak self] _ in
                self?.didTapSaveToPasswordManager()
            },
        )

        let saveManuallyButton = UIButton(
            configuration: .largeSecondary(title: OWSLocalizedString(
                "REGISTRATION_SIGNAL_LOGIN_DETAILS_SAVE_MANUALLY_BUTTON",
                comment: "Button on the 'Signal Login details' screen to save the Signal Login manually.",
            )),
            primaryAction: UIAction { [weak self] _ in
                self?.didTapSaveManually()
            },
        )

        stackView.addArrangedSubview(
            [saveToPasswordManagerButton, saveManuallyButton].enclosedInVerticalStackView(isFullWidthButtons: true),
        )

        NSLayoutConstraint.activate([
            saveManuallyButton.heightAnchor.constraint(equalTo: saveToPasswordManagerButton.heightAnchor),
        ])
    }

    // MARK: Card

    private func buildCardView() -> UIView {
        let cardView = UIView()
        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.layer.shadowColor = UIColor.black.cgColor
        cardView.layer.shadowOpacity = 0.2
        cardView.layer.shadowRadius = 10
        cardView.layer.shadowOffset = CGSize(width: 0, height: 4)

        // The card artwork already includes the "Signal" wordmark.
        let backgroundImageView = UIImageView(image: .signalLoginCard)
        backgroundImageView.translatesAutoresizingMaskIntoConstraints = false
        backgroundImageView.contentMode = .scaleAspectFill
        backgroundImageView.clipsToBounds = true
        backgroundImageView.layer.cornerRadius = Constants.cardCornerRadius
        backgroundImageView.layer.cornerCurve = .continuous
        cardView.addSubview(backgroundImageView)

        let accountField = buildCardField(
            title: OWSLocalizedString(
                "REGISTRATION_SIGNAL_LOGIN_DETAILS_ACCOUNT_LABEL",
                comment: "Label above the partially hidden account ID on the 'Signal Login details' screen.",
            ),
            value: state.aci.serviceIdUppercaseString,
        )
        let recoveryField = buildCardField(
            title: OWSLocalizedString(
                "REGISTRATION_SIGNAL_LOGIN_DETAILS_RECOVERY_LABEL",
                comment: "Label above the partially hidden recovery key on the 'Signal Login details' screen.",
            ),
            value: state.aep.forDisplay.displayString,
        )

        let fieldsStackView = UIStackView(arrangedSubviews: [accountField, recoveryField])
        fieldsStackView.translatesAutoresizingMaskIntoConstraints = false
        fieldsStackView.axis = .horizontal
        fieldsStackView.alignment = .top
        fieldsStackView.distribution = .equalSpacing

        var viewDetailsConfig = UIButton.Configuration.filled()
        viewDetailsConfig.title = OWSLocalizedString(
            "REGISTRATION_SIGNAL_LOGIN_DETAILS_VIEW_DETAILS_BUTTON",
            comment: "Button on the Signal Login card on the 'Signal Login details' screen to show the full account ID and recovery key.",
        )
        viewDetailsConfig.titleTextAttributesTransformer = .defaultFont(.dynamicTypeSubheadlineClamped.semibold())
        viewDetailsConfig.baseForegroundColor = .Signal.ColorBase.labelPrimary
        viewDetailsConfig.baseBackgroundColor = .Signal.ColorBase.button
        viewDetailsConfig.cornerStyle = .capsule
        let viewDetailsButton = UIButton(
            configuration: viewDetailsConfig,
            primaryAction: UIAction { [weak self] _ in
                self?.didTapViewDetails()
            },
        )

        let viewDetailsButtonContainer = UIView.transparentContainer()
        viewDetailsButtonContainer.translatesAutoresizingMaskIntoConstraints = false
        viewDetailsButtonContainer.addSubview(viewDetailsButton)
        viewDetailsButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            viewDetailsButton.topAnchor.constraint(equalTo: viewDetailsButtonContainer.topAnchor),
            viewDetailsButton.bottomAnchor.constraint(equalTo: viewDetailsButtonContainer.bottomAnchor),
            viewDetailsButton.centerXAnchor.constraint(equalTo: viewDetailsButtonContainer.centerXAnchor),
            viewDetailsButton.leadingAnchor.constraint(greaterThanOrEqualTo: viewDetailsButtonContainer.leadingAnchor),
            viewDetailsButton.trailingAnchor.constraint(lessThanOrEqualTo: viewDetailsButtonContainer.trailingAnchor),
        ])

        cardView.addSubview(fieldsStackView)
        cardView.addSubview(viewDetailsButtonContainer)

        let insets = Constants.cardContentInsets
        // Keep the artwork's proportions unless larger text needs more room.
        let aspectRatioConstraint = cardView.heightAnchor.constraint(
            equalTo: cardView.widthAnchor,
            multiplier: Constants.cardAspectRatio,
        )
        aspectRatioConstraint.priority = .defaultHigh
        NSLayoutConstraint.activate([
            aspectRatioConstraint,
            backgroundImageView.topAnchor.constraint(equalTo: cardView.topAnchor),
            backgroundImageView.bottomAnchor.constraint(equalTo: cardView.bottomAnchor),
            backgroundImageView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            backgroundImageView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),

            fieldsStackView.centerYAnchor.constraint(equalTo: backgroundImageView.centerYAnchor),
            fieldsStackView.leadingAnchor.constraint(equalTo: backgroundImageView.leadingAnchor, constant: insets.leading),
            fieldsStackView.trailingAnchor.constraint(equalTo: backgroundImageView.trailingAnchor, constant: -insets.trailing),
            fieldsStackView.topAnchor.constraint(greaterThanOrEqualTo: backgroundImageView.topAnchor),
            fieldsStackView.bottomAnchor.constraint(lessThanOrEqualTo: viewDetailsButtonContainer.bottomAnchor),

            viewDetailsButtonContainer.topAnchor.constraint(
                greaterThanOrEqualTo: fieldsStackView.bottomAnchor,
                constant: -insets.bottom,
            ),
            viewDetailsButtonContainer.bottomAnchor.constraint(equalTo: backgroundImageView.bottomAnchor, constant: -insets.bottom),
            viewDetailsButtonContainer.leadingAnchor.constraint(equalTo: backgroundImageView.leadingAnchor, constant: insets.leading),
            viewDetailsButtonContainer.trailingAnchor.constraint(equalTo: backgroundImageView.trailingAnchor, constant: -insets.trailing),
        ])

        return cardView
    }

    /// A title above a value that is masked except for its last few characters.
    private func buildCardField(title: String, value: String) -> UIView {
        let titleLabel = UILabel()
        titleLabel.font = .dynamicTypeBodyClamped
        titleLabel.textColor = .Signal.ColorBase.labelSecondary
        titleLabel.text = title

        let visibleSuffix = String(value.suffix(Constants.maskedValueVisibleCharacterCount))
        let valueLabel = UILabel()
        valueLabel.font = .monospacedSystemFont(ofSize: UIFont.dynamicTypeSubheadlineClamped.pointSize, weight: .regular)
        valueLabel.textColor = .Signal.ColorBase.labelPrimary
        valueLabel.attributedText = NSAttributedString(
            string: "•••• " + visibleSuffix,
            attributes: [.kern: 2], // Add a bit of spacing between the characters
        )
        valueLabel.accessibilityLabel = String(
            format: OWSLocalizedString(
                "REGISTRATION_SIGNAL_LOGIN_DETAILS_MASKED_VALUE_ACCESSIBILITY_FORMAT",
                comment: "Accessibility label for a partially hidden value on the Signal Login card.",
            ),
            visibleSuffix,
        )

        let stackView = UIStackView(arrangedSubviews: [titleLabel, valueLabel])
        stackView.axis = .vertical
        stackView.alignment = .leading
        stackView.spacing = Constants.cardFieldSpacing
        return stackView
    }

    // MARK: Actions

    private func didTapViewDetails() {
        // TODO[#less]: Show the full account ID and recovery key.
    }

    private func didTapSaveToPasswordManager() {
        // TODO[#less]: Save the Signal Login to a password manager.
    }

    private func didTapSaveManually() {
        // TODO[#less]: Manually save the Signal Login.
    }
}

// MARK: -

#if DEBUG

private class PreviewRegistrationSignalLoginDetailsPresenter: RegistrationSignalLoginDetailsPresenter {
}

@available(iOS 17, *)
#Preview {
    let state = RegistrationSignalLoginDetailsState(
        aci: Aci.randomForTesting(),
        aep: AccountEntropyPool(),
    )
    let presenter = PreviewRegistrationSignalLoginDetailsPresenter()
    return UINavigationController(
        rootViewController: RegistrationSignalLoginDetailsViewController(
            state: state,
            presenter: presenter,
        ),
    )
}

#endif
