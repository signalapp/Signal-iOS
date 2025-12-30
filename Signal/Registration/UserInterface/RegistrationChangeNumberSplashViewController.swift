//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

// MARK: - RegistrationChangeNumberSplashPresenter

protocol RegistrationChangeNumberSplashPresenter: AnyObject {
    func continueFromSplash()

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
            imageView.widthAnchor.constraint(lessThanOrEqualToConstant: 80),
            imageView.heightAnchor.constraint(lessThanOrEqualToConstant: 80),
        ])
        return imageView
    }()

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .Signal.groupedBackground
        navigationItem.rightBarButtonItem = .cancelButton { [weak self] in
            self?.presenter?.exitRegistration()
        }

        // UI Elements
        let heroImageCircle = OWSLayerView.circleView()
        heroImageCircle.backgroundColor = .Signal.secondaryFill
        heroImageCircle.addSubview(heroImageView)
        let heroImageContainer = UIView.container()
        heroImageContainer.addSubview(heroImageCircle)
        heroImageView.translatesAutoresizingMaskIntoConstraints = false
        heroImageCircle.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            heroImageView.centerXAnchor.constraint(equalTo: heroImageCircle.centerXAnchor),
            heroImageView.centerYAnchor.constraint(equalTo: heroImageCircle.centerYAnchor),

            heroImageCircle.widthAnchor.constraint(equalToConstant: 112),
            heroImageCircle.heightAnchor.constraint(equalToConstant: 112),

            heroImageCircle.topAnchor.constraint(equalTo: heroImageContainer.topAnchor),
            heroImageCircle.leadingAnchor.constraint(greaterThanOrEqualTo: heroImageContainer.leadingAnchor),
            heroImageCircle.centerXAnchor.constraint(equalTo: heroImageContainer.centerXAnchor),
            heroImageCircle.bottomAnchor.constraint(equalTo: heroImageContainer.bottomAnchor),
        ])
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

        let stackView = addStaticContentStackView(arrangedSubviews: [
            heroImageContainer,
            titleLabel,
            subtitleLabel,
            .vStretchingSpacer(),
            continueButton.enclosedInVerticalStackView(isFullWidthButton: true),
        ])
        stackView.setCustomSpacing(24, after: heroImageContainer)

        updateContents()
    }

    private func updateContents() {
        let heroImageName = Theme.isDarkThemeEnabled ? "change-number-dark-40" : "change-number-light-40"
        heroImageView.image = UIImage(named: heroImageName)
        heroImageView.sizeToFit()
    }

    private func didTapContinue() {
        presenter?.continueFromSplash()
    }
}

// MARK: -

#if DEBUG

private class PreviewRegistrationChangeNumberSplashPresenter: RegistrationChangeNumberSplashPresenter {
    func continueFromSplash() {
        print("continueFromSplash")
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
