//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import Lottie
import SignalServiceKit

open class HeroSheetViewController: StackSheetViewController {
    public enum Hero {
        /// Scaled image to display at the top of the sheet
        case image(UIImage)
        /// Lottie name and height to display at the top of the sheet
        case animation(named: String, height: CGFloat)
        case circleIcon(
            icon: UIImage,
            iconSize: CGFloat,
            tintColor: UIColor,
            backgroundColor: UIColor,
        )
    }

    public enum Element {
        case button(Button)
        case hero(Hero)
    }

    public struct Button {
        public enum Action {
            case dismiss
            case custom((HeroSheetViewController) -> Void)
        }

        public enum Style {
            case primary
            case secondary
            case secondaryDestructive
        }

        fileprivate let title: String
        fileprivate let action: Action
        fileprivate let style: Style

        public init(title: String, style: Style = .primary, action: Action) {
            self.title = title
            self.style = style
            self.action = action
        }

        public init(title: String, action: @escaping (_: HeroSheetViewController) -> Void) {
            self.init(title: title, action: .custom(action))
        }

        public static func dismissing(title: String, style: Style = .primary) -> Button {
            Button(title: title, style: style, action: .dismiss)
        }

        public var configuration: UIButton.Configuration {
            switch style {
            case .primary:
                return .largePrimary(title: title)

            case .secondary:
                return .largeSecondary(title: title)

            case .secondaryDestructive:
                var config: UIButton.Configuration = .largeSecondary(title: title)
                config.baseForegroundColor = .Signal.red
                return config
            }
        }
    }

    private let hero: Hero
    private let titleText: String
    private let bodyText: String
    private let primary: Element
    private let secondary: Element?

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
        secondaryButton: Button? = nil,
    ) {
        self.hero = hero
        self.titleText = title
        self.bodyText = body
        self.primary = .button(primaryButton)
        self.secondary = secondaryButton.map { .button($0) }
        super.init()
    }

    public init(
        hero: Hero,
        title: String,
        body: String,
        primary: Element,
        secondary: Element? = nil,
    ) {
        self.hero = hero
        self.titleText = title
        self.bodyText = body
        self.primary = primary
        self.secondary = secondary
        super.init()
    }

    // .formSheet makes a blank sheet appear behind it
    override public var modalPresentationStyle: UIModalPresentationStyle {
        willSet {
            if newValue == .formSheet {
                owsFailDebug("Can't use formSheet for interactive sheets")
            }
        }
    }

    override public var stackViewInsets: UIEdgeInsets {
        .init(top: 8, leading: 24, bottom: 32, trailing: 24)
    }

    override public func viewDidLoad() {
        super.viewDidLoad()

        let heroView = viewForHero(hero)
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

        let primaryButtonView = viewForElement(primary)
        self.stackView.addArrangedSubview(primaryButtonView)
        self.stackView.setCustomSpacing(20, after: primaryButtonView)

        if let secondary {
            let secondaryButtonView = viewForElement(secondary)
            self.stackView.addArrangedSubview(secondaryButtonView)
        }
    }

    private func viewForHero(_ hero: Hero) -> UIView {
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
        return heroView
    }

    private func viewForElement(_ element: Element) -> UIView {
        switch element {
        case .button(let button):
            let buttonView = self.buttonView(for: button)
            buttonView.configuration = button.configuration
            return buttonView
        case .hero(let hero):
            return viewForHero(hero)
        }
    }

    private func buttonView(for button: Button) -> UIButton {
        UIButton(
            type: .system,
            primaryAction: UIAction { [weak self] _ in
                guard let self else { return }
                switch button.action {
                case .dismiss:
                    self.dismiss(animated: true)
                case .custom(let closure):
                    closure(self)
                }
            },
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
        primaryButton: .dismissing(title: CommonStrings.continueButton),
    ))
}

@available(iOS 17, *)
#Preview("Animated") {
    SheetPreviewViewController(sheet: HeroSheetViewController(
        hero: .animation(named: "linking-device-light", height: 192),
        title: LocalizationNotNeeded("Scan QR Code"),
        body: LocalizationNotNeeded("Use this device to scan the QR code displayed on the device you want to link"),
        primaryButton: .dismissing(title: CommonStrings.okayButton),
    ))
}

@available(iOS 17, *)
#Preview("Circle icon") {
    SheetPreviewViewController(sheet: HeroSheetViewController(
        hero: .circleIcon(
            icon: UIImage(named: "key")!,
            iconSize: 35,
            tintColor: UIColor.Signal.label,
            backgroundColor: UIColor.Signal.background,
        ),
        title: LocalizationNotNeeded("No Recovery Key?"),
        body: LocalizationNotNeeded("Backups can’t be recovered without their 64-digit recovery code. If you’ve lost your recovery key Signal can’t help restore your backup.\n\nIf you have your old device you can view your recovery key in Settings > Chats > Signal Backups. Then tap View recovery key."),
        primaryButton: .dismissing(title: LocalizationNotNeeded("Skip & Don’t Restore")),
        secondaryButton: .dismissing(title: CommonStrings.learnMore),
    ))
}

@available(iOS 17, *)
#Preview("Footer animation") {
    SheetPreviewViewController(sheet: HeroSheetViewController(
        hero: .image(UIImage(named: "transfer_complete")!),
        title: LocalizationNotNeeded("Continue on your other device"),
        body: LocalizationNotNeeded("Continue transferring your account on your other device."),
        primary: .hero(.animation(named: "circular_indeterminate", height: 60)),
    ))
}
#endif
