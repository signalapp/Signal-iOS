//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import BonMot

class ResearchMegaphone: MegaphoneView {
    init(experienceUpgrade: ExperienceUpgrade, fromViewController: UIViewController) {
        super.init(experienceUpgrade: experienceUpgrade)
        imageName = "researchMegaphone"

        titleText = NSLocalizedString("RESEARCH_MEGAPHONE_TITLE",
                                      comment: "Title for research megaphone")
        bodyText = NSLocalizedString("RESEARCH_MEGAPHONE_BODY",
                                     comment: "Body for research megaphone")

        setButtons(
            primary: Button(title: CommonStrings.learnMore) {
                let vc = UINavigationController(rootViewController: ResearchModal())
                fromViewController.present(vc, animated: true)
            },
            secondary: Button(title: CommonStrings.dismissButton) { [weak self] in
                self?.markAsComplete()
                self?.dismiss()
            }
        )
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private class ResearchModal: UIViewController {
    override func loadView() {
        view = UIScrollView()
        view.backgroundColor = Theme.backgroundColor

        let heroImageView = UIImageView(image: #imageLiteral(resourceName: "researchModalHero"))
        view.addSubview(heroImageView)
        heroImageView.autoPinWidthToSuperview()
        heroImageView.autoPinEdge(toSuperviewEdge: .top)

        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.layoutMargins = UIEdgeInsets(top: 16, leading: 32, bottom: 16, trailing: 32)

        view.addSubview(stackView)
        stackView.autoPinEdge(.top, to: .bottom, of: heroImageView)
        stackView.autoPinEdge(toSuperviewEdge: .bottom)
        stackView.autoPinWidthToSuperview()
        stackView.autoMatch(.width, to: .width, of: view)

        let labelStyle = StringStyle(
            .font(.ows_dynamicTypeBody2),
            .color(Theme.primaryTextColor),
            .xmlRules([
                .style("bold", StringStyle(.font(UIFont.ows_dynamicTypeBody2.ows_semibold)))
            ])
        )

        let label = UILabel()
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.attributedText = NSLocalizedString(
            "RESEARCH_MODAL_PLEA",
            comment: "Text explaining why the user should take the survey"
        ).styled(with: labelStyle)
        stackView.addArrangedSubview(label)

        stackView.addArrangedSubview(.spacer(withHeight: 48))

        let takeTheSurveyButton = OWSFlatButton()
        takeTheSurveyButton.setBackgroundColors(upColor: .ows_accentBlue)
        takeTheSurveyButton.useDefaultCornerRadius()
        takeTheSurveyButton.setAttributedTitle(
            NSAttributedString.composed(of: [
                NSLocalizedString(
                    "RESEARCH_MODAL_TAKE_SURVEY",
                    comment: "Button text for taking the research survey"
                ),
                Special.noBreakSpace,
                #imageLiteral(resourceName: "open-20").withRenderingMode(.alwaysTemplate).styled(with: .baselineOffset(-4))
            ]).styled(with:
                .font(UIFont.ows_dynamicTypeBody.ows_semibold),
                .color(.ows_white)
            )
        )
        takeTheSurveyButton.autoSetDimension(.height, toSize: OWSFlatButton.heightForFont(.ows_dynamicTypeBody))
        takeTheSurveyButton.setPressedBlock { [weak self] in
            ExperienceUpgradeManager.clearExperienceUpgradeWithSneakyTransaction(.researchMegaphone1)
            self?.dismiss(animated: true)
            UIApplication.shared.open(
                URL(string: "https://surveys.signalusers.org/s3")!,
                options: [:],
                completionHandler: nil
            )
        }

        stackView.addArrangedSubview(takeTheSurveyButton)

        stackView.addArrangedSubview(.spacer(withHeight: 8))

        let noThanksButton = OWSFlatButton()
        noThanksButton.setBackgroundColors(upColor: Theme.isDarkThemeEnabled ? .ows_gray75 : .ows_gray05)
        noThanksButton.useDefaultCornerRadius()
        noThanksButton.setTitle(
            title: NSLocalizedString(
                "RESEARCH_MODAL_NO_THANKS",
                comment: "Button text for declining the research modal"
            ),
            font: UIFont.ows_dynamicTypeBody.ows_semibold,
            titleColor: Theme.accentBlueColor
        )
        noThanksButton.autoSetDimension(.height, toSize: OWSFlatButton.heightForFont(.ows_dynamicTypeBody))
        noThanksButton.setPressedBlock { [weak self] in
            ExperienceUpgradeManager.clearExperienceUpgradeWithSneakyTransaction(.researchMegaphone1)
            self?.dismiss(animated: true)
        }

        stackView.addArrangedSubview(noThanksButton)

        stackView.addArrangedSubview(.spacer(withHeight: 16))

        let footerLabel = UILabel()
        footerLabel.numberOfLines = 0
        footerLabel.lineBreakMode = .byWordWrapping
        footerLabel.font = .ows_dynamicTypeCaption1
        footerLabel.textColor = Theme.secondaryTextAndIconColor
        footerLabel.textAlignment = .center
        footerLabel.text = NSLocalizedString(
            "RESEARCH_MODAL_FOOTER",
            comment: "Text for the research modal footer"
        )
        stackView.addArrangedSubview(footerLabel)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString(
            "RESEARCH_MODAL_TITLE",
            comment: "Title for the research megaphone modal"
        )
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .stop,
            target: self,
            action: #selector(didPressCloseButton)
        )
    }

    @objc
    func didPressCloseButton() {
        dismiss(animated: true)
    }
}
