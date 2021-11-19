//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit
import UIKit
import SignalMessaging

class ChangePhoneNumberSplashViewController: OWSViewController {

    private let changePhoneNumberController: ChangePhoneNumberController

    private let rootView = UIStackView()

    public init(changePhoneNumberController: ChangePhoneNumberController) {
        self.changePhoneNumberController = changePhoneNumberController
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("SETTINGS_CHANGE_PHONE_NUMBER_VIEW_TITLE",
                                  comment: "Title for the 'change phone number' views in settings.")

        createContents()
    }

    private func createContents() {
        rootView.axis = .vertical
        rootView.alignment = .fill
        rootView.isLayoutMarginsRelativeArrangement = true
        rootView.layoutMargins = UIEdgeInsets(hMargin: 20, vMargin: 0)
        view.addSubview(rootView)
        rootView.autoPinEdge(toSuperviewSafeArea: .leading)
        rootView.autoPinEdge(toSuperviewSafeArea: .trailing)
        rootView.autoPin(toTopLayoutGuideOf: self, withInset: 0)
        self.autoPinView(toBottomOfViewControllerOrKeyboard: rootView, avoidNotch: true)

        updateContents()
    }

    public override func applyTheme() {
        super.applyTheme()

        updateContents()
    }

    private func updateContents() {
        view.backgroundColor = OWSTableViewController2.tableBackgroundColor(isUsingPresentedStyle: true)

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
        titleLabel.font = .ows_dynamicTypeTitle2.ows_semibold
        titleLabel.textColor = Theme.primaryTextColor
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        titleLabel.lineBreakMode = .byWordWrapping

        let descriptionLabel = UILabel()
        descriptionLabel.text = NSLocalizedString("SETTINGS_CHANGE_PHONE_NUMBER_SPLASH_DESCRIPTION",
                                            comment: "Description text in the 'change phone number splash' view.")
        descriptionLabel.font = .ows_dynamicTypeBody
        descriptionLabel.textColor = Theme.secondaryTextAndIconColor
        descriptionLabel.textAlignment = .center
        descriptionLabel.numberOfLines = 0
        descriptionLabel.lineBreakMode = .byWordWrapping

        let continueButton = OWSFlatButton.button(title: CommonStrings.continueButton,
                                                  font: UIFont.ows_dynamicTypeBody.ows_semibold,
                                                  titleColor: .ows_white,
                                                  backgroundColor: .ows_accentBlue,
                                                  target: self,
                                                  selector: #selector(didTapContinue))
        continueButton.autoSetHeightUsingFont()
        continueButton.cornerRadius = 8

        let cancelButton = OWSFlatButton.button(title: CommonStrings.cancelButton,
                                                font: UIFont.ows_dynamicTypeBody,
                                                titleColor: .ows_accentBlue,
                                                backgroundColor: .clear,
                                                target: self,
                                                selector: #selector(didTapCancel))
        cancelButton.autoSetHeightUsingFont()
        cancelButton.cornerRadius = 8

        rootView.removeAllSubviews()
        rootView.addArrangedSubviews([
            UIView.spacer(withHeight: 40),
            heroStack,
            UIView.spacer(withHeight: 24),
            titleLabel,
            UIView.spacer(withHeight: 12),
            descriptionLabel,
            UIView.vStretchingSpacer(),
            continueButton,
            UIView.spacer(withHeight: 20),
            cancelButton
        ])
    }

    @objc
    private func didTapCancel(_ sender: UIButton) {
        AssertIsOnMainThread()

        changePhoneNumberController.cancelFlow(viewController: self)
    }

    @objc
    private func didTapContinue(_ sender: UIButton) {
        let view = ChangePhoneNumberInputViewController(changePhoneNumberController: changePhoneNumberController)
        self.navigationController?.pushViewController(view, animated: true)
    }
}
