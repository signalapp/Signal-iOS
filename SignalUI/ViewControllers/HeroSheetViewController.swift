//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import Lottie

public class HeroSheetViewController: StackSheetViewController {
    public enum Hero {
        /// Scaled image to display at the top of the sheet
        case image(UIImage)
        /// Lottie name and height to display at the top of the sheet
        case animation(named: String, height: CGFloat)
        case circleIcon(
            icon: UIImage,
            iconSize: CGFloat,
            tintColor: UIColor,
            backgroundColor: UIColor
        )
    }

    public struct Button {
        public enum Action {
            case dismiss
            case custom(() -> Void)
        }

        fileprivate let title: String
        fileprivate let action: Action

        private init(title: String, action: Action) {
            self.title = title
            self.action = action
        }

        public init(title: String, action: @escaping () -> Void) {
            self.init(title: title, action: .custom(action))
        }

        public static func dismissing(title: String) -> Button {
            Button(title: title, action: .dismiss)
        }
    }

    private let hero: Hero
    private let titleText: String
    private let bodyText: String
    private let primaryButton: Button
    private let secondaryButton: Button?

    /// Creates a hero image sheet with a CTA button.
    /// - Parameters:
    ///   - hero: The main content to display at the top of the sheet
    ///   - title: Localized title text
    ///   - body: Localized body text
    ///   - primaryButton: The title and action for the CTA button
    ///   - secondaryButton: The title and action for an optional secondary button
    ///   If `nil`, the button will dismiss the sheet.
    public init(
        hero: Hero,
        title: String,
        body: String,
        primaryButton: Button,
        secondaryButton: Button? = nil
    ) {
        self.hero = hero
        self.titleText = title
        self.bodyText = body
        self.primaryButton = primaryButton
        self.secondaryButton = secondaryButton
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
        case let .circleIcon(icon, iconSize, tintColor, backgroundColor):
            let iconView = UIImageView(image: icon)
            iconView.tintColor = tintColor
            heroView = UIView()
            let backgroundView = UIView()
            heroView.addSubview(backgroundView)
            backgroundView.autoPinHeightToSuperview()
            backgroundView.autoHCenterInSuperview()
            backgroundView.contentMode = .center
            backgroundView.autoSetDimensions(to: .square(64))
            backgroundView.layer.cornerRadius = 32
            backgroundView.backgroundColor = backgroundColor
            backgroundView.addSubview(iconView)
            iconView.autoCenterInSuperview()
            iconView.autoSetDimensions(to: .square(iconSize))
        }

        self.stackView.addArrangedSubview(heroView)
        self.stackView.setCustomSpacing(16, after: heroView)

        let titleLabel = UILabel()
        self.stackView.addArrangedSubview(titleLabel)
        self.stackView.setCustomSpacing(12, after: titleLabel)
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

        let primaryButtonView = self.buttonView(for: primaryButton)
        self.stackView.addArrangedSubview(primaryButtonView)
        self.stackView.setCustomSpacing(20, after: primaryButtonView)
        var buttonConfiguration = UIButton.Configuration.filled()
        var buttonTitleAttributes = AttributeContainer()
        buttonTitleAttributes.font = .dynamicTypeHeadline
        buttonTitleAttributes.foregroundColor = .white
        buttonConfiguration.attributedTitle = AttributedString(
            self.primaryButton.title,
            attributes: buttonTitleAttributes
        )
        buttonConfiguration.contentInsets = .init(hMargin: 16, vMargin: 14)
        buttonConfiguration.background.cornerRadius = 10
        buttonConfiguration.background.backgroundColor = UIColor.Signal.ultramarine
        primaryButtonView.configuration = buttonConfiguration

        if let secondaryButton {
            let secondaryButtonView = self.buttonView(for: secondaryButton)
            self.stackView.addArrangedSubview(secondaryButtonView)
            var buttonConfiguration = UIButton.Configuration.plain()
            var buttonTitleAttributes = AttributeContainer()
            buttonTitleAttributes.font = .dynamicTypeHeadline
            buttonTitleAttributes.foregroundColor = UIColor.Signal.ultramarine
            buttonConfiguration.attributedTitle = AttributedString(
                secondaryButton.title,
                attributes: buttonTitleAttributes
            )
            secondaryButtonView.configuration = buttonConfiguration
        }
    }

    private func buttonView(for button: Button) -> UIButton {
        UIButton(
            type: .system,
            primaryAction: UIAction { [weak self] _ in
                switch button.action {
                case .dismiss:
                    self?.dismiss(animated: true)
                case .custom(let closure):
                    closure()
                }
            }
        )
    }
}

#if DEBUG
@available(iOS 17, *)
#Preview("Image") {
    SheetPreviewViewController(sheet: HeroSheetViewController(
        hero: .image(UIImage(named: "linked-devices")!),
        title: LocalizationNotNeeded("Finish linking on your other device"),
        body: LocalizationNotNeeded("Finish linking Signal on your other device."),
        primaryButton: .dismissing(title: CommonStrings.continueButton)
    ))
}

@available(iOS 17, *)
#Preview("Animated") {
    SheetPreviewViewController(sheet: HeroSheetViewController(
        hero: .animation(named: "linking-device-light", height: 192),
        title: LocalizationNotNeeded("Scan QR Code"),
        body: LocalizationNotNeeded("Use this device to scan the QR code displayed on the device you want to link"),
        primaryButton: .dismissing(title: CommonStrings.okayButton)
    ))
}

@available(iOS 17, *)
#Preview("Circle icon") {
    SheetPreviewViewController(sheet: HeroSheetViewController(
        hero: .circleIcon(
            icon: UIImage(named: "key")!,
            iconSize: 35,
            tintColor: UIColor.Signal.label,
            backgroundColor: UIColor.Signal.background
        ),
        title: LocalizationNotNeeded("No Backup Key?"),
        body: LocalizationNotNeeded("Backups can’t be recovered without their 64-digit recovery code. If you’ve lost your backup key Signal can’t help restore your backup.\n\nIf you have your old device you can view your backup key in Settings > Chats > Signal Backups. Then tap View backup key."),
        primaryButton: .dismissing(title: LocalizationNotNeeded("Skip & Don’t Restore")),
        secondaryButton: .dismissing(title: CommonStrings.learnMore)
    ))
}
#endif
