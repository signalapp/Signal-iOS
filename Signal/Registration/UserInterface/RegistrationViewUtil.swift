//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import SignalUI

// MARK: - Strings

extension String {
    var e164FormattedAsPhoneNumberWithoutBreaks: String {
        let formatted = PhoneNumber.bestEffortLocalizedPhoneNumber(e164: self)
        return formatted.replacingOccurrences(of: " ", with: "\u{00a0}")
    }
}

// MARK: - Layout margins

extension NSDirectionalEdgeInsets {
    static func layoutMarginsForRegistration(
        _ horizontalSizeClass: UIUserInterfaceSizeClass
    ) -> NSDirectionalEdgeInsets {
        switch horizontalSizeClass {
        case .regular:
            return NSDirectionalEdgeInsets(top: 0, leading: 112, bottom: 112, trailing: 112)
        case .unspecified, .compact:
            fallthrough
        @unknown default:
            return NSDirectionalEdgeInsets(top: 0, leading: 32, bottom: 32, trailing: 32)
        }
    }
}

// MARK: - Labels

extension UILabel {
    static func titleLabelForRegistration(text: String) -> UILabel {
        let result = UILabel()
        result.text = text
        result.textColor = .Signal.label
        result.font = UIFont.dynamicTypeTitle1Clamped.semibold()
        result.numberOfLines = 0
        result.lineBreakMode = .byWordWrapping
        result.textAlignment = .center
        result.accessibilityTraits = [ .staticText, .header ]
        return result
    }

    static func explanationLabelForRegistration(text: String) -> UILabel {
        let result = UILabel()
        result.textColor = .Signal.secondaryLabel
        result.font = .dynamicTypeBodyClamped
        result.text = text
        result.numberOfLines = 0
        result.textAlignment = .center
        result.lineBreakMode = .byWordWrapping
        return result
    }
}

// MARK: - Buttons

extension UIButton {
    class func registrationChoiceButton(
        title: String,
        subtitle: String,
        iconName: String,
        primaryAction: UIAction? = nil
    ) -> Self {
        let button = UIButton(configuration: .gray(), primaryAction: primaryAction)

        // Set up button background.
        if #available(iOS 26, *) {
            button.configuration?.background.cornerRadius = 26
        } else {
            button.configuration?.background.cornerRadius = 8
        }
        button.configuration?.baseBackgroundColor = .Signal.quaternaryFill

        // Add content view.
        let contentConfiguration = RegistrationChoiceButtonContentConfiguration(
            title: title,
            subtitle: subtitle,
            iconName: iconName
        )
        let contentView = contentConfiguration.makeContentView()
        button.addSubview(contentView)
        contentView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            contentView.topAnchor.constraint(equalTo: button.topAnchor),
            contentView.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: button.bottomAnchor)
        ])

        button.accessibilityLabel = contentConfiguration.title
        button.accessibilityHint = contentConfiguration.subtitle

        return button as! Self
    }
}

private struct RegistrationChoiceButtonContentConfiguration: UIContentConfiguration {
    var title: String
    var subtitle: String
    var iconName: String
    var imageSize: CGFloat?

    func makeContentView() -> UIView & UIContentView {
        RegistrationChoiceButtonContentView(configuration: self)
    }

    func updated(for state: UIConfigurationState) -> RegistrationChoiceButtonContentConfiguration {
        // Looks the same.
        self
    }
}

private class RegistrationChoiceButtonContentView: UIView, UIContentView {
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let disclosureView = UILabel()

    init(configuration: RegistrationChoiceButtonContentConfiguration) {
        super.init(frame: .zero)
        setupViews()
        self.configuration = configuration
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var currentConfiguration: RegistrationChoiceButtonContentConfiguration!

    var configuration: UIContentConfiguration {
        get { currentConfiguration }
        set {
            guard let config = newValue as? RegistrationChoiceButtonContentConfiguration else { return }
            currentConfiguration = config
            apply(configuration: config)
        }
    }

    func apply(configuration: RegistrationChoiceButtonContentConfiguration) {
        titleLabel.text = configuration.title
        subtitleLabel.text = configuration.subtitle
        iconView.image = UIImage(named: configuration.iconName)?.withRenderingMode(.alwaysTemplate)
        iconView.sizeToFit()
    }

    private func setupViews() {
        isUserInteractionEnabled = false

        // Icon
        let iconContainer = UIView()
        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = .Signal.ultramarine
        iconContainer.addSubview(iconView)
        iconContainer.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iconContainer.widthAnchor.constraint(equalToConstant: 48),
            iconContainer.heightAnchor.constraint(equalToConstant: 48),
            iconView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
            iconView.trailingAnchor.constraint(greaterThanOrEqualTo: iconContainer.trailingAnchor),
            iconView.topAnchor.constraint(greaterThanOrEqualTo: iconContainer.topAnchor),
        ])

        // Labels
        titleLabel.font = .dynamicTypeHeadline
        titleLabel.textColor = .Signal.label
        titleLabel.numberOfLines = 0
        titleLabel.lineBreakMode = .byWordWrapping

        subtitleLabel.font = .dynamicTypeFootnote
        subtitleLabel.textColor = .Signal.secondaryLabel
        subtitleLabel.numberOfLines = 0
        subtitleLabel.lineBreakMode = .byWordWrapping

        let vStack = UIStackView(arrangedSubviews: [
            titleLabel,
            subtitleLabel,
        ])
        vStack.axis = .vertical
        vStack.spacing = 2

        // Disclosure Indicator
        let disclosureView = UIImageView(image: UIImage(imageLiteralResourceName: "chevron-right-20"))
        disclosureView.tintColor = .Signal.tertiaryLabel
        disclosureView.translatesAutoresizingMaskIntoConstraints = false
        // This must be unnecessary but I've observed that without this constraint
        // UIKit does not split `titleLabel` in two lines when it should, clipping it instead.
        disclosureView.widthAnchor.constraint(equalToConstant: 20).isActive = true

        let hStack = UIStackView(arrangedSubviews: [
            iconContainer,
            vStack,
            disclosureView,
        ])
        hStack.setCustomSpacing(20, after: vStack)
        hStack.alignment = .center
        hStack.axis = .horizontal
        hStack.spacing = 12
        hStack.isLayoutMarginsRelativeArrangement = true
        hStack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 21, leading: 12, bottom: 21, trailing: 16)
        hStack.isUserInteractionEnabled = false

        addSubview(hStack)
        hStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hStack.topAnchor.constraint(equalTo: topAnchor),
            hStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            hStack.bottomAnchor.constraint(equalTo: bottomAnchor),
            hStack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }
}

// MARK: - Action sheets

extension ActionSheetController {
    enum RegistrationVerificationConfirmationMode {
        case sms
        case voice
    }

    static func forRegistrationVerificationConfirmation(
        mode: RegistrationVerificationConfirmationMode,
        e164: String,
        didConfirm: @escaping () -> Void,
        didRequestEdit: @escaping () -> Void
    ) -> ActionSheetController {
        let message: String
        switch mode {
        case .sms:
            message = OWSLocalizedString(
                "REGISTRATION_VIEW_PHONE_NUMBER_CONFIRMATION_ALERT_MESSAGE",
                comment: "Message for confirmation alert during phone number registration."
            )
        case .voice:
            message = OWSLocalizedString(
                "REGISTRATION_PHONE_NUMBER_VOICE_CODE_ALERT_MESSAGE",
                comment: "Message for confirmation alert when requesting a voice code during phone number registration."
            )

        }
        let result = ActionSheetController(
            title: {
                let format = OWSLocalizedString(
                    "REGISTRATION_VIEW_PHONE_NUMBER_CONFIRMATION_ALERT_TITLE_FORMAT",
                    comment: "Title for confirmation alert during phone number registration. Embeds {{phone number}}."
                )
                return String(format: format, e164.e164FormattedAsPhoneNumberWithoutBreaks)
            }(),
            message: message
        )

        let confirmButtonTitle = CommonStrings.yesButton
        result.addAction(.init(title: confirmButtonTitle) { _ in didConfirm() })

        let editButtonTitle = OWSLocalizedString(
            "REGISTRATION_VIEW_PHONE_NUMBER_CONFIRMATION_EDIT_BUTTON",
            comment: "A button allowing user to cancel registration and edit a phone number"
        )
        result.addAction(.init(title: editButtonTitle) { _ in didRequestEdit() })

        return result
    }
}

// MARK: - Alerts

extension UIAlertController {
    static func registrationAppUpdateBanner() -> UIAlertController {
        let result = UIAlertController(
            title: OWSLocalizedString(
                "REGISTRATION_CANNOT_CONTINUE_WITHOUT_UPDATING_APP_TITLE",
                comment: "During (re)registration, users may need to update their app to continue. They'll be presented with an alert if this is the case, prompting them to update. This is the title on that alert."
            ),
            message: OWSLocalizedString(
                "REGISTRATION_CANNOT_CONTINUE_WITHOUT_UPDATING_APP_DESCRIPTION",
                comment: "During (re)registration, users may need to update their app to continue. They'll be presented with an alert if this is the case, prompting them to update. This is the description text on that alert."
            ),
            preferredStyle: .alert
        )

        let updateAction = UIAlertAction(
            title: OWSLocalizedString(
                "REGISTRATION_CANNOT_CONTINUE_WITHOUT_UPDATING_APP_ACTION",
                comment: "During (re)registration, users may need to update their app to continue. They'll be presented with an alert if this is the case, prompting them to update. This is the action button on that alert."
            ),
            style: .default
        ) { _ in
            UIApplication.shared.open(TSConstants.appStoreUrl)
        }
        result.addAction(updateAction)
        result.preferredAction = updateAction

        return result
    }
}
