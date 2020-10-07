//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import Lottie

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

        animationView.addRedBorder()

        let vStack = UIStackView()
        vStack.axis = .vertical
        vStack.alignment = .fill
        view.addSubview(vStack)
        vStack.autoPinWidthToSuperview(withMargin: hMargin)
        vStack.autoPinBottomToSuperviewMargin(withInset: ScaleFromIPhone5(10))
        // The title label actually overlaps the hero image because it has a long shadow
        // and we want the text to partially sit on top of this.
//        titleLabel.autoPinEdge(.top, to: .bottom, of: animationView, withOffset: -10)
        vStack.autoPinEdge(.top, to: .bottom, of: animationView)

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.textAlignment = .center
        titleLabel.font = UIFont.ows_dynamicTypeTitle1.ows_semibold
        titleLabel.textColor = Theme.primaryTextColor
        titleLabel.minimumScaleFactor = 0.5
        titleLabel.adjustsFontSizeToFitWidth = true
        vStack.addArrangedSubview(titleLabel)
        vStack.addArrangedSubview(UIView.spacer(withHeight: 6))

        let bodyLabel = UILabel()
        bodyLabel.text = body
        bodyLabel.font = UIFont.ows_dynamicTypeBody
        bodyLabel.textColor = Theme.primaryTextColor
        bodyLabel.numberOfLines = 0
        bodyLabel.lineBreakMode = .byWordWrapping
        bodyLabel.textAlignment = .center
        vStack.addArrangedSubview(bodyLabel)
        vStack.addArrangedSubview(UIView.spacer(withHeight: 25))

        let footerLabel = UILabel()
        footerLabel.text = NSLocalizedString("SPLASH_MEGAPHONE_GROUPS_V2_MENTIONS_NAMES_SPLASH_FOOTER",
                                           comment: "Footer for 'groups v2 and mentions' splash screen")
        footerLabel.font = UIFont.ows_dynamicTypeSubheadline
        footerLabel.textColor = Theme.secondaryTextAndIconColor
        footerLabel.numberOfLines = 0
        footerLabel.lineBreakMode = .byWordWrapping
        footerLabel.textAlignment = .center
        vStack.addArrangedSubview(footerLabel)
        vStack.addArrangedSubview(UIView.spacer(withHeight: 25))

        let okayButton = OWSFlatButton.button(title: CommonStrings.okayButton,
                                              font: UIFont.ows_dynamicTypeBody.ows_semibold,
                                              titleColor: .white,
                                              backgroundColor: .ows_accentBlue,
                                              target: self,
                                              selector: #selector(didTapOkayButton))
        okayButton.autoSetHeightUsingFont()
        vStack.addArrangedSubview(okayButton)
        vStack.addArrangedSubview(UIView.spacer(withHeight: 4))

        let learnMoreButton = OWSFlatButton.button(title: CommonStrings.learnMore,
                                              font: UIFont.ows_dynamicTypeBody,
                                              titleColor: Theme.accentBlueColor,
                                              backgroundColor: Theme.backgroundColor,
                                              target: self,
                                              selector: #selector(didTapLearnMoreButton))
        learnMoreButton.autoSetHeightUsingFont()
        vStack.addArrangedSubview(learnMoreButton)
    }

    @objc
    func didTapOkayButton(_ sender: UIButton) {
        dismiss(animated: true)
    }

    @objc
    func didTapLearnMoreButton(_ sender: UIButton) {
        // TODO:
//        let vc = ProfileViewController(mode: .experienceUpgrade) { [weak self] _ in
//            self?.dismiss(animated: true)
//        }
//        navigationController?.pushViewController(vc, animated: true)
    }
}
