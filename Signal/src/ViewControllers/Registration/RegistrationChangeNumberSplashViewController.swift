//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import UIKit
import SignalMessaging

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
    }

    public var preferredNavigationBarStyle: OWSNavigationBarStyle {
        return .solid
    }

    public var navbarBackgroundColorOverride: UIColor? {
        return view.backgroundColor
    }

    private let bottomContainer = UIView()
    private let scrollingStack = UIStackView()

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.setHidesBackButton(true, animated: false)

        createContents()
    }

    private func createContents() {
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(didPressCancel)
        )

        let scrollView = UIScrollView()
        view.addSubview(scrollView)
        scrollView.autoPinEdge(toSuperviewSafeArea: .leading)
        scrollView.autoPinEdge(toSuperviewSafeArea: .trailing)
        scrollView.autoPin(toTopLayoutGuideOf: self, withInset: 0)

        scrollingStack.axis = .vertical
        scrollingStack.alignment = .fill
        scrollingStack.isLayoutMarginsRelativeArrangement = true
        scrollingStack.layoutMargins = UIEdgeInsets(hMargin: 20, vMargin: 0)
        scrollView.addSubview(scrollingStack)
        scrollingStack.autoMatch(.width, to: .width, of: scrollView)
        scrollingStack.autoPinEdgesToSuperviewEdges()

        bottomContainer.layoutMargins = UIEdgeInsets(hMargin: 20, vMargin: 0)
        view.addSubview(bottomContainer)
        bottomContainer.autoPinEdge(toSuperviewSafeArea: .leading)
        bottomContainer.autoPinEdge(toSuperviewSafeArea: .trailing)
        bottomContainer.autoPinEdge(.top, to: .bottom, of: scrollView)
        bottomContainer.autoPinEdge(.bottom, to: .bottom, of: keyboardLayoutGuideViewSafeArea)

        updateContents()
    }

    public override func themeDidChange() {
        super.themeDidChange()

        updateContents()
    }

    private func updateContents() {
        view.backgroundColor = OWSTableViewController2.tableBackgroundColor(isUsingPresentedStyle: true)
        owsNavigationController?.updateNavbarAppearance()

        let heroImageName = (Theme.isDarkThemeEnabled
                             ? "change-number-dark-40"
                             : "change-number-light-40")
        let heroImage = UIImage(named: heroImageName)
        let heroImageView = UIImageView(image: heroImage)
        heroImageView.autoSetDimension(.width, toSize: 80, relation: .lessThanOrEqual)
        heroImageView.autoSetDimension(.height, toSize: 80, relation: .lessThanOrEqual)
        let heroCircleView = OWSLayerView.circleView(size: 112)
        heroCircleView.backgroundColor = (Theme.isDarkThemeEnabled
                                          ? UIColor.ows_white
                                          : UIColor.ows_black).withAlphaComponent(0.05)
        heroCircleView.addSubview(heroImageView)
        heroImageView.autoCenterInSuperview()
        let heroStack = UIStackView(arrangedSubviews: [heroCircleView])
        heroStack.axis = .vertical
        heroStack.alignment = .center

        let titleLabel = UILabel()
        titleLabel.text = NSLocalizedString("SETTINGS_CHANGE_PHONE_NUMBER_SPLASH_TITLE",
                                            comment: "Title text in the 'change phone number splash' view.")
        titleLabel.font = .dynamicTypeTitle2.semibold()
        titleLabel.textColor = Theme.primaryTextColor
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        titleLabel.lineBreakMode = .byWordWrapping

        let descriptionLabel = UILabel()
        descriptionLabel.text = NSLocalizedString("SETTINGS_CHANGE_PHONE_NUMBER_SPLASH_DESCRIPTION",
                                            comment: "Description text in the 'change phone number splash' view.")
        descriptionLabel.font = .dynamicTypeBody
        descriptionLabel.textColor = Theme.secondaryTextAndIconColor
        descriptionLabel.textAlignment = .center
        descriptionLabel.numberOfLines = 0
        descriptionLabel.lineBreakMode = .byWordWrapping

        let continueButton = OWSFlatButton.button(title: CommonStrings.continueButton,
                                                  font: UIFont.dynamicTypeBody.semibold(),
                                                  titleColor: .ows_white,
                                                  backgroundColor: .ows_accentBlue,
                                                  target: self,
                                                  selector: #selector(didTapContinue))
        continueButton.autoSetHeightUsingFont()
        continueButton.cornerRadius = 8

        scrollingStack.removeAllSubviews()
        scrollingStack.addArrangedSubviews([
            UIView.spacer(withHeight: 40),
            heroStack,
            UIView.spacer(withHeight: 24),
            titleLabel,
            UIView.spacer(withHeight: 12),
            descriptionLabel,
            UIView.vStretchingSpacer(minHeight: 16)
        ])

        bottomContainer.removeAllSubviews()
        bottomContainer.addSubview(continueButton)
        continueButton.autoPinEdgesToSuperviewMargins()
    }

    @objc
    private func didPressCancel() {
        presenter?.exitRegistration()
    }

    @objc
    private func didTapContinue(_ sender: UIButton) {
        presenter?.continueFromSplash()
    }
}
