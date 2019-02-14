//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import UIKit
import PromiseKit

@objc
public class OnboardingBaseViewController: OWSViewController {

    // Unlike a delegate, we can and should retain a strong reference to the OnboardingController.
    let onboardingController: OnboardingController

    @objc
    public init(onboardingController: OnboardingController) {
        self.onboardingController = onboardingController

        super.init(nibName: nil, bundle: nil)

        self.shouldUseTheme = false
    }

    @available(*, unavailable, message: "use other init() instead.")
    required public init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    // MARK: - Factory Methods

    func titleLabel(text: String) -> UILabel {
        let titleLabel = UILabel()
        titleLabel.text = text
        titleLabel.textColor = Theme.primaryColor
        titleLabel.font = UIFont.ows_dynamicTypeTitle2.ows_mediumWeight()
        titleLabel.numberOfLines = 0
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.textAlignment = .center
        return titleLabel
    }

    func explanationLabel(explanationText: String, linkText: String, selector: Selector) -> UILabel {
        let explanationText = NSAttributedString(string: explanationText)
            .rtlSafeAppend(NSAttributedString(string: " "))
            .rtlSafeAppend(linkText,
                           attributes: [
                            NSAttributedStringKey.foregroundColor: UIColor.ows_materialBlue
                ])
        let explanationLabel = UILabel()
        explanationLabel.textColor = Theme.secondaryColor
        explanationLabel.font = UIFont.ows_dynamicTypeCaption1
        explanationLabel.attributedText = explanationText
        explanationLabel.numberOfLines = 0
        explanationLabel.textAlignment = .center
        explanationLabel.lineBreakMode = .byWordWrapping
        explanationLabel.isUserInteractionEnabled = true
        explanationLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: selector))
        return explanationLabel
    }

    func button(title: String, selector: Selector) -> OWSFlatButton {
        // TODO: Make sure this all fits if dynamic font sizes are maxed out.
        let buttonHeight: CGFloat = 48
        let button = OWSFlatButton.button(title: title,
                                          font: OWSFlatButton.fontForHeight(buttonHeight),
                                          titleColor: .white,
                                          backgroundColor: .ows_materialBlue,
                                          target: self,
                                          selector: selector)
        button.autoSetDimension(.height, toSize: buttonHeight)
        return button
    }

    // MARK: - View Lifecycle

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        // TODO: Is there a better way to do this?
        if let navigationController = self.navigationController as? OWSNavigationController {
            SignalApp.shared().signUpFlowNavigationController = navigationController
        } else {
            owsFailDebug("Missing or invalid navigationController")
        }
    }

    // MARK: - Orientation

    public override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }

    public override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }
}
