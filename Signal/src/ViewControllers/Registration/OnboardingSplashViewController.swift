//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import UIKit
import PromiseKit

@objc
public class OnboardingSplashViewController: OnboardingBaseViewController {

    override public func loadView() {
        super.loadView()

        view.backgroundColor = Theme.backgroundColor
        view.layoutMargins = .zero

        // TODO:
        //        navigationItem.title = NSLocalizedString("SETTINGS_BACKUP", comment: "Label for the backup view in app settings.")

        let heroImage = UIImage(named: "onboarding_splash_hero")
        let heroImageView = UIImageView(image: heroImage)
        heroImageView.contentMode = .scaleAspectFit
        heroImageView.layer.minificationFilter = kCAFilterTrilinear
        heroImageView.layer.magnificationFilter = kCAFilterTrilinear
        heroImageView.setCompressionResistanceLow()
        heroImageView.setContentHuggingVerticalLow()

        let titleLabel = self.titleLabel(text: NSLocalizedString("ONBOARDING_SPLASH_TITLE", comment: "Title of the 'onboarding splash' view."))
        view.addSubview(titleLabel)
        titleLabel.autoPinWidthToSuperviewMargins()
        titleLabel.autoPinEdge(toSuperviewMargin: .top)

        // TODO: Finalize copy.
        let explanationLabel = self.explanationLabel(explanationText: NSLocalizedString("ONBOARDING_SPLASH_EXPLANATION",
                                                                                        comment: "Explanation in the 'onboarding splash' view."),
                                                     linkText: NSLocalizedString("ONBOARDING_SPLASH_TERM_AND_PRIVACY_POLICY",
                                                                                 comment: "Link to the 'terms and privacy policy' in the 'onboarding splash' view."),
                                                     selector: #selector(explanationLabelTapped))

        // TODO: Make sure this all fits if dynamic font sizes are maxed out.
        let continueButton = self.button(title: NSLocalizedString("BUTTON_CONTINUE",
                                                                 comment: "Label for 'continue' button."),
                                                    selector: #selector(continuePressed))
        view.addSubview(continueButton)

        let stackView = UIStackView(arrangedSubviews: [
            heroImageView,
            UIView.spacer(withHeight: 22),
            titleLabel,
            UIView.spacer(withHeight: 56),
            explanationLabel,
            UIView.spacer(withHeight: 40),
            continueButton
            ])
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.layoutMargins = UIEdgeInsets(top: 32, left: 32, bottom: 32, right: 32)
        stackView.isLayoutMarginsRelativeArrangement = true
        view.addSubview(stackView)
        stackView.autoPinWidthToSuperviewMargins()
        stackView.autoPin(toTopLayoutGuideOf: self, withInset: 0)
        stackView.autoPin(toBottomLayoutGuideOf: self, withInset: 0)
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        self.navigationController?.isNavigationBarHidden = true
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        self.navigationController?.isNavigationBarHidden = true
    }

     // MARK: - Events

    @objc func explanationLabelTapped(sender: UIGestureRecognizer) {
        guard sender.state == .recognized else {
            return
        }
        guard let url = URL(string: kLegalTermsUrlString) else {
            owsFailDebug("Invalid URL.")
            return
        }
        UIApplication.shared.openURL(url)
    }

    @objc func continuePressed() {
        Logger.info("")

        onboardingController.onboardingSplashDidComplete(viewController: self)
    }
}
