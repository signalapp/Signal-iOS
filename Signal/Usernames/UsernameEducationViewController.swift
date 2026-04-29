//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SafariServices
import SignalServiceKit
import SignalUI

class UsernameEducationViewController: OWSViewController {

    /// Completion called once the user taps 'Continue' in the education prompt
    var continueCompletion: (() -> Void)?

    var prefersNavigationBarHidden: Bool { true }

    // MARK: UIViewController

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .Signal.background

        // Pill handle.
        let handleSize = CGSize(width: 52, height: 5) // Match InteractiveSheetViewController
        let handleView = PillView()
        handleView.backgroundColor = .Signal.primaryFill // Match InteractiveSheetViewController
        handleView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(handleView)
        NSLayoutConstraint.activate([
            handleView.widthAnchor.constraint(equalToConstant: handleSize.width),
            handleView.heightAnchor.constraint(equalToConstant: handleSize.height),
            handleView.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            handleView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        ])

        // Main content view.
        let stackView = addStaticContentStackView(
            arrangedSubviews: [],
            isScrollable: true,
        )
        stackView.spacing = 40 // space between helper rows

        // Spacer at the top.
        let topSpacer = UIView.transparentSpacer()
        topSpacer.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            topSpacer.heightAnchor.constraint(equalToConstant: 40), // 44 dp total with stackView's spacing€
        ])
        stackView.addArrangedSubview(topSpacer)

        // Title.
        let titleLabel = UILabel.titleLabelForRegistration(text: OWSLocalizedString(
            "USERNAME_EDUCATION_TITLE",
            comment: "Title to set up signal username",
        ))
        titleLabel.adjustsFontForContentSizeCategory = true
        stackView.addArrangedSubview(titleLabel)

        // Helper text.
        stackView.addArrangedSubview(createHelperTextRow(
            iconName: "phone-48-color",
            title: OWSLocalizedString(
                "USERNAME_EDUCATION_PRIVACY_TITLE",
                comment: "Title for phone number privacy section of the username education sheet",
            ),
            description: OWSLocalizedString(
                "USERNAME_EDUCATION_PRIVACY_DESCRIPTION",
                comment: "Description of phone number privacy on the username education sheet",
            ),
        ))

        stackView.addArrangedSubview(createHelperTextRow(
            iconName: "usernames-48-color",
            title: OWSLocalizedString(
                "USERNAME_EDUCATION_USERNAME_TITLE",
                comment: "Title for usernames section on the username education sheet",
            ),
            description: OWSLocalizedString(
                "USERNAME_EDUCATION_USERNAME_DESCRIPTION",
                comment: "Description of usernames on the username education sheet",
            ),
        ))

        stackView.addArrangedSubview(createHelperTextRow(
            iconName: "qr-codes-48-color",
            title: OWSLocalizedString(
                "USERNAME_EDUCATION_LINK_TITLE",
                comment: "Title for the username links and QR codes section on the username education sheet",
            ),
            description: OWSLocalizedString(
                "USERNAME_EDUCATION_LINK_DESCRIPTION",
                comment: "Description of username links and QR codes on the username education sheet",
            ),
        ))

        // Vertical spacer.
        let verticalSpacer = UIView.transparentSpacer()
        stackView.addArrangedSubview(verticalSpacer)
        stackView.setCustomSpacing(0, after: verticalSpacer) // avoid double space: above and below spacer view

        // Buttons at the bottom.
        let continueButton = UIButton(
            configuration: .largePrimary(title: OWSLocalizedString(
                "USERNAME_EDUCATION_SET_UP_BUTTON",
                comment: "Label for the 'set up' button on the username education sheet",
            )),
            primaryAction: UIAction { [weak self] _ in
                self?.didTapContinue()
            },
        )

        let dismissButton = UIButton(
            configuration: .largeSecondary(title: CommonStrings.notNowButton),
            primaryAction: UIAction { [weak self] _ in
                self?.didTapDismiss()
            },
        )
        stackView.addArrangedSubview(UIStackView.verticalButtonStack(buttons: [continueButton, dismissButton]))
    }

    private func createHelperTextRow(
        iconName: String,
        title: String,
        description: String,
    ) -> UIView {
        let iconView = UIImageView(image: UIImage(named: iconName))
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalTo: iconView.heightAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 48),
        ])

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .dynamicTypeHeadline
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 0
        titleLabel.textAlignment = .natural
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.textColor = .Signal.label

        let bodyLabel = UILabel()
        bodyLabel.text = description
        bodyLabel.font = .dynamicTypeBodyClamped
        bodyLabel.adjustsFontForContentSizeCategory = true
        bodyLabel.numberOfLines = 0
        bodyLabel.textAlignment = .natural
        bodyLabel.lineBreakMode = .byWordWrapping
        bodyLabel.textColor = .Signal.secondaryLabel

        let textStack = UIStackView(
            arrangedSubviews: [
                titleLabel,
                bodyLabel,
            ],
        )
        textStack.axis = .vertical
        textStack.spacing = 4

        let stackView = UIStackView(arrangedSubviews: [iconView, textStack])
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.preservesSuperviewLayoutMargins = true
        stackView.directionalLayoutMargins.leading = 20
        stackView.directionalLayoutMargins.trailing = 20
        stackView.spacing = 20
        stackView.alignment = .top

        return stackView
    }

    // MARK: Actions

    private func didTapContinue() {
        dismiss(animated: true) {
            self.continueCompletion?()
        }
    }

    private func didTapDismiss() {
        dismiss(animated: true)
    }
}

// MARK: -

#if DEBUG

@available(iOS 17, *)
#Preview {
    return UsernameEducationViewController()
}

#endif
