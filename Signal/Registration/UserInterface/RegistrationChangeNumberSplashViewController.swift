//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

// MARK: - RegistrationChangeNumberSplashPresenter

protocol RegistrationChangeNumberSplashPresenter: AnyObject {
    func continueFromSplash()

    func canChangeNumber() -> ChangeNumberAllowedResult

    func exitRegistration()
}

class RegistrationChangeNumberSplashViewController: OWSViewController, OWSNavigationChildController {

    private weak var presenter: RegistrationChangeNumberSplashPresenter?

    init(presenter: RegistrationChangeNumberSplashPresenter) {
        self.presenter = presenter
        super.init()
        navigationItem.hidesBackButton = true
    }

    var preferredNavigationBarStyle: OWSNavigationBarStyle {
        return .solid
    }

    var navbarBackgroundColorOverride: UIColor? {
        return view.backgroundColor
    }

    private lazy var heroImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.addConstraints([
            imageView.widthAnchor.constraint(lessThanOrEqualToConstant: 160),
            imageView.heightAnchor.constraint(lessThanOrEqualToConstant: 160),
        ])
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .Signal.groupedBackground
        navigationItem.rightBarButtonItem = .cancelButton { [weak self] in
            self?.presenter?.exitRegistration()
        }

        let titleLabel = UILabel.titleLabelForRegistration(
            text: OWSLocalizedString(
                "SETTINGS_CHANGE_PHONE_NUMBER_SPLASH_TITLE",
                comment: "Title text in the 'change phone number splash' view.",
            ),
        )
        let subtitleLabel = UILabel.explanationLabelForRegistration(
            text: OWSLocalizedString(
                "SETTINGS_CHANGE_PHONE_NUMBER_SPLASH_DESCRIPTION",
                comment: "Description text in the 'change phone number splash' view.",
            ),
        )
        let continueButton = UIButton(
            configuration: .largePrimary(title: CommonStrings.continueButton),
            primaryAction: UIAction { [weak self] _ in
                self?.didTapContinue()
            },
        )

        let heroImageView = heroImageView
        let stackView = addStaticContentStackView(arrangedSubviews: [
            heroImageView,
            titleLabel,
            subtitleLabel,
            .vStretchingSpacer(),
            continueButton.enclosedInVerticalStackView(isFullWidthButton: true),
        ])
        stackView.setCustomSpacing(24, after: heroImageView)

        updateContents()
    }

    private func updateContents() {
        let heroImageName = "change_number"
        heroImageView.image = UIImage(named: heroImageName)
        heroImageView.sizeToFit()
    }

    private func didTapContinue() {
        guard let presenter else {
            owsFailDebug("Missing presenter")
            return
        }

        // check for bool here to determine if timeout needs to be shown
        switch presenter.canChangeNumber() {
        case .success:
            presenter.continueFromSplash()
        case .retryAfter(let backoff):
            let title = OWSLocalizedString(
                "SETTINGS_CHANGE_PHONE_NUMBER_SPLASH_CANT_CHANGE_TITLE",
                comment: "Title text for sheet displaying the 'Can't change phone number splash' message.",
            )

            let bodyTextFormat = OWSLocalizedString(
                "SETTINGS_CHANGE_PHONE_NUMBER_SPLASH_CANT_CHANGE_BODY",
                tableName: "PluralAware",
                comment: "Title text for sheet displaying the 'Can't change phone number splash' message. Embeds {{number of hours before retry}}",
            )

            let bodyTextFormatted = String.localizedStringWithFormat(
                bodyTextFormat,
                Int(ceil(Double(backoff) / Double(1 * TimeInterval.hour))),
            )

            let bodyAttributedString = NSAttributedString(string: bodyTextFormatted)
                .styled(
                    with:
                    .font(.dynamicTypeBody),
                    .color(UIColor.Signal.label),
                )

            let heroImage = UIImage(named: "change_number_error")!

            let actionSheet = ActionSheetController(
                title: title,
                message: bodyAttributedString,
                image: heroImage,
            )
            actionSheet.addAction(ActionSheetAction.ok)

            present(actionSheet, animated: true)
        }
    }
}

// MARK: -

#if DEBUG

private class PreviewRegistrationChangeNumberSplashPresenter: RegistrationChangeNumberSplashPresenter {
    func continueFromSplash() {
        print("continueFromSplash")
    }

    func canChangeNumber() -> ChangeNumberAllowedResult {
        print("canChangeNumber")
        return .success
    }

    func exitRegistration() {
        print("exitRegistration")
    }
}

@available(iOS 17, *)
#Preview {
    let presenter = PreviewRegistrationChangeNumberSplashPresenter()
    return UINavigationController(
        rootViewController: RegistrationChangeNumberSplashViewController(
            presenter: presenter,
        ),
    )
}

#endif
