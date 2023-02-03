//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit

@objc
public class Deprecated_RegistrationBaseViewController: OWSViewController, OWSNavigationChildController {

    // MARK: - Factory Methods

    func createTitleLabel(text: String) -> UILabel {
        let titleLabel = UILabel()
        titleLabel.text = text
        titleLabel.textColor = Theme.primaryTextColor
        titleLabel.font = UIFont.ows_dynamicTypeTitle1Clamped.ows_semibold
        titleLabel.numberOfLines = 0
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.textAlignment = .center
        return titleLabel
    }

    func createExplanationLabel(explanationText: String) -> UILabel {
        let explanationLabel = UILabel()
        explanationLabel.textColor = Theme.secondaryTextAndIconColor
        explanationLabel.font = UIFont.ows_dynamicTypeSubheadlineClamped
        explanationLabel.text = explanationText
        explanationLabel.numberOfLines = 0
        explanationLabel.textAlignment = .center
        explanationLabel.lineBreakMode = .byWordWrapping
        return explanationLabel
    }

    @objc
    public var primaryLayoutMargins: UIEdgeInsets {
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
        primaryButton(title: title, target: self, selector: selector)
    }

    func primaryButton(title: String, target: Any, selector: Selector) -> OWSFlatButton {
        let button = OWSFlatButton.button(
            title: title,
            font: UIFont.ows_dynamicTypeBodyClamped.ows_semibold,
            titleColor: .white,
            backgroundColor: .ows_accentBlue,
            target: target,
            selector: selector)
        button.button.layer.cornerRadius = 14
        button.contentEdgeInsets = UIEdgeInsets(hMargin: 4, vMargin: 14)
        return button
    }

    func linkButton(title: String, selector: Selector) -> OWSFlatButton {
        linkButton(title: title, target: self, selector: selector)
    }

    func linkButton(title: String, target: Any, selector: Selector) -> OWSFlatButton {
        let button = OWSFlatButton.button(
            title: title,
            font: UIFont.ows_dynamicTypeSubheadlineClamped,
            titleColor: Theme.accentBlueColor,
            backgroundColor: .clear,
            target: target,
            selector: selector)
        button.enableMultilineLabel()
        button.button.layer.cornerRadius = 8
        button.contentEdgeInsets = UIEdgeInsets(hMargin: 4, vMargin: 8)
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
    }

    @objc
    func navigateBack() {
        navigationController?.popViewController(animated: true)
    }

    public var prefersNavigationBarHidden: Bool {
        true
    }

    public var shouldCancelNavigationBack: Bool {
        true
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
    @objc
    public let primaryView = UIView()

    override public func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        primaryView.layoutMargins = primaryLayoutMargins
    }

    // MARK: - Orientation

    public override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return UIDevice.current.isIPad ? .all : .portrait
    }
}
