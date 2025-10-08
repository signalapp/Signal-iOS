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

    public init(presenter: RegistrationChangeNumberSplashPresenter) {
        self.presenter = presenter
        super.init()
        navigationItem.hidesBackButton = true
    }

    public var preferredNavigationBarStyle: OWSNavigationBarStyle {
        return .solid
    }

    public var navbarBackgroundColorOverride: UIColor? {
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
        let heroImageCircle = OWSLayerView.circleView(size: 112)
        heroImageCircle.backgroundColor = .Signal.secondaryFill
        heroImageCircle.addSubview(heroImageView)
        heroImageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            heroImageView.centerXAnchor.constraint(equalTo: heroImageCircle.centerXAnchor),
            heroImageView.centerYAnchor.constraint(equalTo: heroImageCircle.centerYAnchor),
        ])
        let titleLabel = UILabel.titleLabelForRegistration(
            text: OWSLocalizedString(
                "SETTINGS_CHANGE_PHONE_NUMBER_SPLASH_TITLE",
                comment: "Title text in the 'change phone number splash' view."
            )
        )
        let subtitleLabel = UILabel.explanationLabelForRegistration(
            text: OWSLocalizedString(
                "SETTINGS_CHANGE_PHONE_NUMBER_SPLASH_DESCRIPTION",
                comment: "Description text in the 'change phone number splash' view."
            )
        )
        let continueButton = UIButton(
            configuration: .largePrimary(title: CommonStrings.continueButton),
            primaryAction: UIAction { [weak self] _ in
                self?.didTapContinue()
            }
        )
        let buttonContainer = UIView.container()
        buttonContainer.addSubview(continueButton)
        continueButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            continueButton.topAnchor.constraint(equalTo: buttonContainer.topAnchor),
            continueButton.leadingAnchor.constraint(equalTo: buttonContainer.leadingAnchor, constant: 22),
            continueButton.centerXAnchor.constraint(equalTo: buttonContainer.centerXAnchor),
            continueButton.bottomAnchor.constraint(equalTo: buttonContainer.bottomAnchor, constant: -16),
        ])

        // Layout
        let scrollView = UIScrollView()
        scrollView.preservesSuperviewLayoutMargins = true
        view.addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.frameLayoutGuide.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.frameLayoutGuide.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.frameLayoutGuide.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            scrollView.frameLayoutGuide.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        let stackView = UIStackView(arrangedSubviews: [
            heroImageCircle,
            titleLabel,
            subtitleLabel,
            .vStretchingSpacer(minHeight: 36),
            buttonContainer
        ])
        stackView.setCustomSpacing(24, after: heroImageCircle)
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 12
        stackView.directionalLayoutMargins.top = 24
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.preservesSuperviewLayoutMargins = true
        scrollView.addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            buttonContainer.widthAnchor.constraint(equalTo: stackView.layoutMarginsGuide.widthAnchor),

            stackView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            stackView.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.frameLayoutGuide.heightAnchor),
            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
        ])

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
            presenter: presenter
        )
    )
}

#endif
