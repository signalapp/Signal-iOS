//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
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

        super.init()

        self.shouldUseTheme = false
    }

    // MARK: - Factory Methods

    func titleLabel(text: String) -> UILabel {
        let titleLabel = UILabel()
        titleLabel.text = text
        titleLabel.textColor = Theme.primaryTextColor
        titleLabel.font = UIFont.ows_dynamicTypeTitle1Clamped.ows_semibold
        titleLabel.numberOfLines = 0
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.textAlignment = .center
        return titleLabel
    }

    func explanationLabel(explanationText: String) -> UILabel {
        let explanationLabel = UILabel()
        explanationLabel.textColor = Theme.secondaryTextAndIconColor
        explanationLabel.font = UIFont.ows_dynamicTypeSubheadlineClamped
        explanationLabel.text = explanationText
        explanationLabel.numberOfLines = 0
        explanationLabel.textAlignment = .center
        explanationLabel.lineBreakMode = .byWordWrapping
        return explanationLabel
    }

    var primaryLayoutMargins: UIEdgeInsets {
        switch traitCollection.horizontalSizeClass {
        case .unspecified, .compact:
            return UIEdgeInsets(top: 32, leading: 32, bottom: 32, trailing: 32)
        case .regular:
            return UIEdgeInsets(top: 112, leading: 112, bottom: 112, trailing: 112)
        @unknown default:
            return UIEdgeInsets(top: 32, leading: 32, bottom: 32, trailing: 32)
        }
    }

    func primaryButton(title: String, selector: Selector) -> OWSFlatButton {
        return button(title: title, selector: selector, titleColor: .white, backgroundColor: .ows_accentBlue)
    }

    func linkButton(title: String, selector: Selector) -> OWSFlatButton {
        return button(title: title, selector: selector, titleColor: Theme.accentBlueColor, backgroundColor: .clear)
    }

    func shouldShowBackButton() -> Bool {
        return onboardingController.isOnboardingModeOverriden
    }

    private func button(title: String, selector: Selector, titleColor: UIColor, backgroundColor: UIColor) -> OWSFlatButton {
        let font = UIFont.ows_dynamicTypeBodyClamped.ows_semibold
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

    public class func horizontallyWrap(primaryButton: UIView) -> UIView {
        primaryButton.autoSetDimension(.width, toSize: 280)

        let buttonWrapper = UIView()
        buttonWrapper.addSubview(primaryButton)

        primaryButton.autoPinEdge(toSuperviewEdge: .top)
        primaryButton.autoPinEdge(toSuperviewEdge: .bottom)
        primaryButton.autoHCenterInSuperview()
        NSLayoutConstraint.autoSetPriority(.defaultLow) {
            primaryButton.autoPinEdge(toSuperviewEdge: .leading)
            primaryButton.autoPinEdge(toSuperviewEdge: .trailing)
        }

        return buttonWrapper
    }

    // MARK: - View Lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()

        primaryView.layoutMargins = primaryLayoutMargins

        self.shouldBottomViewReserveSpaceForKeyboard = true

        if shouldShowBackButton() {
            let backButton = UIButton()
            let backButtonImage = CurrentAppContext().isRTL ? #imageLiteral(resourceName: "NavBarBackRTL") : #imageLiteral(resourceName: "NavBarBack")
            backButton.setTemplateImage(backButtonImage, tintColor: Theme.secondaryTextAndIconColor)
            backButton.addTarget(self, action: #selector(navigateBack), for: .touchUpInside)

            view.addSubview(backButton)
            backButton.autoSetDimensions(to: CGSize(square: 40))
            backButton.autoPinEdge(toSuperviewMargin: .leading)
            backButton.autoPinEdge(toSuperviewMargin: .top)
        }
    }

    @objc func navigateBack() {
        navigationController?.popViewController(animated: true)
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        self.navigationController?.isNavigationBarHidden = true
        // Disable "back" gesture.
        self.navigationController?.navigationItem.backBarButtonItem?.isEnabled = false
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        self.navigationController?.isNavigationBarHidden = true
        // Disable "back" gesture.
        self.navigationController?.navigationItem.backBarButtonItem?.isEnabled = false
    }

    // The margins for `primaryView` will update to reflect the current traitCollection.
    // This includes handling changes to traits - e.g. when splitting an iPad or rotating
    // some iPhones.
    //
    // Subclasses should add primaryView as the single child of self.view and add any further
    // subviews to primaryView.
    //
    // If not for iOS10, we could get rid of primaryView, and manipulate the layoutMargins on
    // self.view directly, however on iOS10, UIKit VC presentation machinery resets the
    // layoutMargins *after* this method is called.
    let primaryView = UIView()
    override public func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        primaryView.layoutMargins = primaryLayoutMargins
    }

    // MARK: - Orientation

    public override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return UIDevice.current.isIPad ? .all : .portrait
    }

    public override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }
}
