//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import Lottie
import SafariServices

class GroupsV2AndMentionsSplash: SplashViewController {

    private static var animationName: String {
        Theme.isDarkThemeEnabled ? "splash_groupsv2_iOS_dark" : "splash_groupsv2_iOS_light"
    }
    private let animationView = AnimationView(name: GroupsV2AndMentionsSplash.animationName)

    override var canDismissWithGesture: Bool { return false }

    // MARK: - View lifecycle

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        animationView.play()
        navigationController?.setNavigationBarHidden(true, animated: false)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setNavigationBarHidden(false, animated: false)
    }

    override func loadView() {

        self.view = UIView.container()
        self.view.backgroundColor = Theme.backgroundColor

        let title = NSLocalizedString("SPLASH_MEGAPHONE_GROUPS_V2_MENTIONS_NAMES_SPLASH_TITLE",
                                      comment: "Header for 'groups v2 and mentions' splash screen")
        let body = NSLocalizedString("SPLASH_MEGAPHONE_GROUPS_V2_MENTIONS_SPLASH_BODY",
                                     comment: "Body text for 'groups v2 and mentions' splash screen")

        let hMargin: CGFloat = ScaleFromIPhone5To7Plus(16, 24)

        animationView.contentMode = .scaleAspectFit
        animationView.loopMode = .playOnce
        animationView.backgroundBehavior = .forceFinish

        view.addSubview(animationView)
        animationView.autoPinTopToSuperviewMargin(withInset: 10)
        animationView.autoPinWidthToSuperview()
        animationView.setContentHuggingLow()
        animationView.setCompressionResistanceLow()

        let topStack = UIStackView()
        topStack.axis = .vertical
        topStack.alignment = .center
        view.addSubview(topStack)
        topStack.autoPinWidthToSuperview(withMargin: hMargin)
        topStack.autoPinEdge(.top, to: .bottom, of: animationView)

        let bottomStack = UIStackView()
        bottomStack.axis = .vertical
        bottomStack.alignment = .fill
        view.addSubview(bottomStack)
        bottomStack.autoPinWidthToSuperview(withMargin: hMargin)
        bottomStack.autoPinBottomToSuperviewMargin(withInset: ScaleFromIPhone5(10))
        bottomStack.autoPinEdge(.top, to: .bottom, of: topStack)

        func buildLabel() -> UILabel {
            let label = UILabel()
            label.textAlignment = .center
            label.numberOfLines = 0
            label.lineBreakMode = .byWordWrapping
            return label
        }

        let titleLabel = buildLabel()
        titleLabel.text = title
        titleLabel.font = UIFont.ows_dynamicTypeTitle1.ows_semibold
        titleLabel.textColor = Theme.primaryTextColor
        titleLabel.numberOfLines = 1
        titleLabel.minimumScaleFactor = 0.5
        titleLabel.adjustsFontSizeToFitWidth = true
        topStack.addArrangedSubview(titleLabel)
        topStack.addArrangedSubview(UIView.spacer(withHeight: 6))

        let bodyLabel = buildLabel()
        bodyLabel.text = body
        bodyLabel.font = UIFont.ows_dynamicTypeBody
        bodyLabel.textColor = Theme.primaryTextColor
        topStack.addArrangedSubview(bodyLabel)
        topStack.addArrangedSubview(UIView.spacer(withHeight: 25))

        let instructionsStack = UIStackView()
        instructionsStack.axis = .horizontal
        instructionsStack.alignment = .center
        instructionsStack.spacing = 10
        topStack.addArrangedSubview(instructionsStack)
        topStack.addArrangedSubview(UIView.spacer(withHeight: 25))

        let instructionsIconView = UIImageView()
        instructionsIconView.setImage(imageName: Theme.iconName(.compose32))
        instructionsIconView.setContentHuggingHigh()
        instructionsStack.addArrangedSubview(instructionsIconView)

        let instructionsLabel1 = buildLabel()
        instructionsLabel1.font = UIFont.ows_dynamicTypeBody
        instructionsLabel1.text = NSLocalizedString("SPLASH_MEGAPHONE_GROUPS_V2_MENTIONS_NAMES_SPLASH_INSTRUCTIONS_JOINER",
                                                    comment: "Joiner symbol in the instructions for 'groups v2 and mentions' splash screen")
        instructionsLabel1.textColor = Theme.primaryTextColor
        instructionsLabel1.setContentHuggingHigh()
        instructionsLabel1.numberOfLines = 1
        instructionsStack.addArrangedSubview(instructionsLabel1)

        let instructionsLabel2 = buildLabel()
        instructionsLabel2.font = UIFont.ows_dynamicTypeBody
        instructionsLabel2.text = NSLocalizedString("SPLASH_MEGAPHONE_GROUPS_V2_MENTIONS_NAMES_SPLASH_INSTRUCTIONS",
                                                    comment: "Instructions for 'groups v2 and mentions' splash screen")
        instructionsLabel2.textColor = Theme.primaryTextColor
        instructionsLabel2.numberOfLines = 1
        instructionsLabel2.setContentHuggingHigh()
        instructionsStack.addArrangedSubview(instructionsLabel2)

        let footerLabel = buildLabel()
        footerLabel.text = NSLocalizedString("SPLASH_MEGAPHONE_GROUPS_V2_MENTIONS_NAMES_SPLASH_FOOTER",
                                           comment: "Footer for 'groups v2 and mentions' splash screen")
        footerLabel.font = UIFont.ows_dynamicTypeSubheadline
        footerLabel.textColor = Theme.secondaryTextAndIconColor
        topStack.addArrangedSubview(footerLabel)
        topStack.addArrangedSubview(UIView.spacer(withHeight: 50))

        let okayButton = OWSFlatButton.button(title: CommonStrings.okayButton,
                                              font: UIFont.ows_dynamicTypeBody.ows_semibold,
                                              titleColor: .white,
                                              backgroundColor: .ows_accentBlue,
                                              target: self,
                                              selector: #selector(didTapOkayButton))
        okayButton.autoSetHeightUsingFont()
        bottomStack.addArrangedSubview(okayButton)
        bottomStack.addArrangedSubview(UIView.spacer(withHeight: 4))

        let learnMoreButton = OWSFlatButton.button(title: CommonStrings.learnMore,
                                              font: UIFont.ows_dynamicTypeBody,
                                              titleColor: Theme.accentBlueColor,
                                              backgroundColor: Theme.backgroundColor,
                                              target: self,
                                              selector: #selector(didTapLearnMoreButton))
        learnMoreButton.autoSetHeightUsingFont()
        bottomStack.addArrangedSubview(learnMoreButton)
    }

    @objc
    func didTapOkayButton(_ sender: UIButton) {
        dismiss(animated: true)
    }

    @objc
    func didTapLearnMoreButton(_ sender: UIButton) {
        dismiss(animated: true) {
            Self.showLearnMoreView()
        }
    }

    private class func showLearnMoreView() {
        guard let url = URL(string: "https://support.signal.org/hc/articles/360007319331") else {
            owsFailDebug("Invalid url.")
            return
        }
        guard let fromViewController = CurrentAppContext().frontmostViewController() else {
            owsFailDebug("Missing fromViewController.")
            return
        }
        let vc = SFSafariViewController(url: url)
        fromViewController.present(vc, animated: true, completion: nil)
    }
}
