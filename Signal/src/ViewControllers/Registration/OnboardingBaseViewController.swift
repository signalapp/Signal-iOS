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
        titleLabel.font = UIFont.ows_dynamicTypeTitle1Clamped.ows_mediumWeight()
        titleLabel.numberOfLines = 0
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.textAlignment = .center
        return titleLabel
    }

    func explanationLabel(explanationText: String) -> UILabel {
        let explanationLabel = UILabel()
        explanationLabel.textColor = Theme.secondaryColor
        explanationLabel.font = UIFont.ows_dynamicTypeSubheadlineClamped
        explanationLabel.text = explanationText
        explanationLabel.numberOfLines = 0
        explanationLabel.textAlignment = .center
        explanationLabel.lineBreakMode = .byWordWrapping
        return explanationLabel
    }

    func button(title: String, selector: Selector) -> OWSFlatButton {
        return button(title: title, selector: selector, titleColor: .white, backgroundColor: .ows_materialBlue)
    }

    func linkButton(title: String, selector: Selector) -> OWSFlatButton {
        return button(title: title, selector: selector, titleColor: .ows_materialBlue, backgroundColor: .white)
    }

    private func button(title: String, selector: Selector, titleColor: UIColor, backgroundColor: UIColor) -> OWSFlatButton {
        let font = UIFont.ows_dynamicTypeBodyClamped.ows_mediumWeight()
        let buttonHeight = OWSFlatButton.heightForFont(font)
        let button = OWSFlatButton.button(title: title,
                                          font: font,
                                          titleColor: titleColor,
                                          backgroundColor: backgroundColor,
                                          target: self,
                                          selector: selector)
        button.autoSetDimension(.height, toSize: buttonHeight)
        return button
    }

    // MARK: - View Lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()

        self.shouldBottomViewReserveSpaceForKeyboard = true
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        self.navigationController?.isNavigationBarHidden = true
        // Disable "back" gesture.
        self.navigationController?.navigationItem.backBarButtonItem?.isEnabled = false

        // TODO: Is there a better way to do this?
        if let navigationController = self.navigationController as? OWSNavigationController {
            SignalApp.shared().signUpFlowNavigationController = navigationController
        } else {
            owsFailDebug("Missing or invalid navigationController")
        }

        view.layoutIfNeeded()
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        self.navigationController?.isNavigationBarHidden = true
        // Disable "back" gesture.
        self.navigationController?.navigationItem.backBarButtonItem?.isEnabled = false
    }

    // MARK: - Orientation

    public override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }

    public override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }
}
