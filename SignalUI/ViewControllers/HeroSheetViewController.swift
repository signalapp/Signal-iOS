//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import Lottie

public class HeroSheetViewController: StackSheetViewController {
    private enum Hero {
        case image(UIImage)
        case animation(named: String, height: CGFloat)
    }

    private let hero: Hero
    private let titleText: String
    private let bodyText: String
    private let buttonTitle: String
    private let buttonAction: (() -> Void)?

    /// Creates a hero image sheet with a CTA button.
    /// - Parameters:
    ///   - heroImage: Scaled image to display at the top of the sheet
    ///   - title: Localized title text
    ///   - body: Localized body text
    ///   - buttonTitle: Title for the CTA button
    ///   - didTapButton: Action for the CTA button.
    ///   If `nil`, the button will dismiss the sheet.
    public init(
        heroImage: UIImage,
        title: String,
        body: String,
        buttonTitle: String,
        didTapButton: (() -> Void)? = nil
    ) {
        self.hero = .image(heroImage)
        self.titleText = title
        self.bodyText = body
        self.buttonTitle = buttonTitle
        self.buttonAction = didTapButton
        super.init()
    }

    /// Creates a hero image sheet with a CTA button.
    /// - Parameters:
    ///   - heroLottieName: Lottie name to display at the top of the sheet
    ///   - heroAnimationHeight: Height for the animation view
    ///   - title: Localized title text
    ///   - body: Localized body text
    ///   - buttonTitle: Title for the CTA button
    ///   - didTapButton: Action for the CTA button.
    ///   If `nil`, the button will dismiss the sheet.
    public init(
        heroAnimationName: String,
        heroAnimationHeight: CGFloat,
        title: String,
        body: String,
        buttonTitle: String,
        didTapButton: (() -> Void)? = nil
    ) {
        self.hero = .animation(named: heroAnimationName, height: heroAnimationHeight)
        self.titleText = title
        self.bodyText = body
        self.buttonTitle = buttonTitle
        self.buttonAction = didTapButton
        super.init()
    }

    public override var stackViewInsets: UIEdgeInsets {
        .init(top: 8, leading: 24, bottom: 32, trailing: 24)
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        let heroView: UIView
        switch hero {
        case let .image(image):
            heroView = UIImageView(image: image)
            heroView.contentMode = .center
        case let .animation(lottieName, height):
            let lottieView = LottieAnimationView(name: lottieName)
            lottieView.autoSetDimension(.height, toSize: height)
            lottieView.contentMode = .scaleAspectFit
            lottieView.loopMode = .loop
            lottieView.play()

            heroView = lottieView
        }

        self.stackView.addArrangedSubview(heroView)
        self.stackView.setCustomSpacing(20, after: heroView)

        let titleLabel = UILabel()
        self.stackView.addArrangedSubview(titleLabel)
        self.stackView.setCustomSpacing(8, after: titleLabel)
        titleLabel.text = self.titleText
        titleLabel.font = .dynamicTypeTitle2.bold()
        titleLabel.numberOfLines = 0
        titleLabel.textAlignment = .center

        let bodyLabel = UILabel()
        self.stackView.addArrangedSubview(bodyLabel)
        self.stackView.setCustomSpacing(32, after: bodyLabel)
        bodyLabel.text = self.bodyText
        bodyLabel.font = .dynamicTypeSubheadline
        bodyLabel.textColor = UIColor.Signal.secondaryLabel
        bodyLabel.numberOfLines = 0
        bodyLabel.textAlignment = .center

        let button = UIButton(type: .system, primaryAction: UIAction { [weak self] _ in
            if let self, let buttonAction {
                buttonAction()
            } else {
                self?.dismiss(animated: true)
            }
        })
        self.stackView.addArrangedSubview(button)
        var buttonConfiguration = UIButton.Configuration.filled()
        var buttonTitleAttributes = AttributeContainer()
        buttonTitleAttributes.font = .dynamicTypeHeadline
        buttonTitleAttributes.foregroundColor = .white
        buttonConfiguration.attributedTitle = AttributedString(
            self.buttonTitle,
            attributes: buttonTitleAttributes
        )
        buttonConfiguration.contentInsets = .init(hMargin: 16, vMargin: 14)
        buttonConfiguration.background.cornerRadius = 10
        buttonConfiguration.background.backgroundColor = UIColor.Signal.ultramarine
        button.configuration = buttonConfiguration
    }
}
