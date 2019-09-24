import NVActivityIndicatorView

@objc(LKNukeDataModal)
final class NukeDataModal : Modal {
    
    // MARK: Lifecycle
    override func populateContentView() {
        // Label
        let titleLabel = UILabel()
        titleLabel.textColor = Theme.primaryColor
        titleLabel.font = UIFont.ows_dynamicTypeHeadlineClamped
        titleLabel.text = NSLocalizedString("Clear All Data", comment: "")
        titleLabel.numberOfLines = 0
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.textAlignment = .center
        // Explanation label
        let explanationLabel = UILabel()
        explanationLabel.font = UIFont.ows_dynamicTypeCaption1Clamped
        explanationLabel.text = NSLocalizedString("Are you sure you want to clear all your data? This will delete your entire account, including all conversations and your personal key pair.", comment: "")
        explanationLabel.numberOfLines = 0
        explanationLabel.textAlignment = .center
        explanationLabel.lineBreakMode = .byWordWrapping
        explanationLabel.textColor = UIColor.ows_white
        // Button stack view
        let nukeButton = OWSFlatButton.button(title: NSLocalizedString("OK", comment: ""), font: .ows_dynamicTypeBodyClamped, titleColor: .white, backgroundColor: .clear, target: self, selector: #selector(nuke))
        nukeButton.setBackgroundColors(upColor: .clear, downColor: .clear)
        let buttonStackView = UIStackView(arrangedSubviews: [ nukeButton, cancelButton ])
        buttonStackView.axis = .horizontal
        buttonStackView.distribution = .fillEqually
        let buttonHeight = cancelButton.button.titleLabel!.font.pointSize * 48 / 17
        nukeButton.set(.height, to: buttonHeight)
        cancelButton.set(.height, to: buttonHeight)
        // Stack view
        let stackView = UIStackView(arrangedSubviews: [ UIView.spacer(withHeight: 2), titleLabel, explanationLabel, buttonStackView ])
        stackView.axis = .vertical
        stackView.spacing = 16
        contentView.addSubview(stackView)
        stackView.pin(.leading, to: .leading, of: contentView, withInset: 16)
        stackView.pin(.top, to: .top, of: contentView, withInset: 16)
        contentView.pin(.trailing, to: .trailing, of: stackView, withInset: 16)
        contentView.pin(.bottom, to: .bottom, of: stackView, withInset: 16)
    }
    
    // MARK: Interaction
    @objc private func nuke() {
        ThreadUtil.deleteAllContent()
        SSKEnvironment.shared.identityManager.clearIdentityKey()
        LokiAPI.clearRandomSnodePool()
        let appDelegate = UIApplication.shared.delegate as! AppDelegate
        appDelegate.stopLongPollerIfNeeded()
        SSKEnvironment.shared.tsAccountManager.resetForReregistration()
        let rootViewController = OnboardingController().initialViewController()
        let navigationController = OWSNavigationController(rootViewController: rootViewController)
        navigationController.isNavigationBarHidden = true
        UIApplication.shared.keyWindow!.rootViewController = navigationController
    }
}
