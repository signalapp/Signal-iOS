//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import BonMot
import Foundation
import Lottie
import SignalServiceKit

open class HeroSheetViewController: StackSheetViewController {
    public enum Hero {
        /// Scaled image to display at the top of the sheet
        case image(UIImage, tintColor: UIColor? = nil)
        /// Lottie name and height to display at the top of the sheet
        case animation(named: String, height: CGFloat)
        case circleIcon(
            icon: UIImage,
            iconSize: CGFloat,
            tintColor: UIColor,
            backgroundColor: UIColor,
        )
    }

    public struct Body {
        public enum TextContent {
            case plain(String)
            case attributed(NSAttributedString)
        }

        public struct BulletPoint {
            public let icon: UIImage
            public let text: String

            public init(icon: UIImage, text: String) {
                self.icon = icon
                self.text = text
            }
        }

        public struct Toggle {
            public let title: String
            public let footer: String?
            public let isOn: Bool
            public let onValueChanged: (_ isEnabled: Bool) -> Void

            public init(
                title: String,
                footer: String?,
                isOn: Bool,
                onValueChanged: @escaping (_ isEnabled: Bool) -> Void,
            ) {
                self.title = title
                self.footer = footer
                self.isOn = isOn
                self.onValueChanged = onValueChanged
            }
        }

        public let textContent: TextContent
        public let textAlignment: NSTextAlignment
        public let textColor: UIColor
        public let bulletPoints: [BulletPoint]
        public let toggle: Toggle?

        public init(
            textContent: TextContent,
            textAlignment: NSTextAlignment = .center,
            textColor: UIColor = .Signal.secondaryLabel,
            bulletPoints: [BulletPoint] = [],
            toggle: Toggle? = nil,
        ) {
            self.textContent = textContent
            self.textAlignment = textAlignment
            self.textColor = textColor
            self.bulletPoints = bulletPoints
            self.toggle = toggle
        }
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

        fileprivate var configuration: UIButton.Configuration {
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

    // MARK: -

    private let hero: Hero
    private let titleText: String?
    private let body: Body
    private let primary: Element?
    private let secondary: Element?

    public init(
        hero: Hero,
        title: String?,
        body: String,
        primaryButton: Button?,
        secondaryButton: Button? = nil,
    ) {
        self.hero = hero
        self.titleText = title
        self.body = Body(textContent: .plain(body))
        self.primary = primaryButton.map { .button($0) }
        self.secondary = secondaryButton.map { .button($0) }
        super.init()
    }

    public init(
        hero: Hero,
        title: String?,
        body: Body,
        primary: Element?,
        secondary: Element?,
    ) {
        self.hero = hero
        self.titleText = title
        self.body = body
        self.primary = primary
        self.secondary = secondary
        super.init()
    }

    // MARK: -

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

        if let titleText {
            let titleLabel = UILabel()
            self.stackView.addArrangedSubview(titleLabel)
            self.stackView.setCustomSpacing(12, after: titleLabel)
            titleLabel.text = titleText
            titleLabel.font = .dynamicTypeTitle2.bold()
            titleLabel.numberOfLines = 0
            titleLabel.textAlignment = .center
        }

        // Use a text view so embedded links in attributed bodies are tappable.
        let bodyTextView = LinkingTextView()
        self.stackView.addArrangedSubview(bodyTextView)
        self.stackView.setCustomSpacing(32, after: bodyTextView)
        switch body.textContent {
        case .plain(let text):
            bodyTextView.text = text
        case .attributed(let attributedText):
            bodyTextView.attributedText = attributedText
        }
        bodyTextView.font = .dynamicTypeSubheadline
        bodyTextView.textColor = body.textColor
        bodyTextView.textAlignment = body.textAlignment

        for bodyBullet in body.bulletPoints {
            let bulletView = viewForBulletPoint(
                bodyBullet,
                textColor: body.textColor,
            )
            self.stackView.addArrangedSubview(bulletView)
            self.stackView.setCustomSpacing(32, after: bulletView)
        }

        if let toggle = body.toggle {
            let toggleView = viewForToggle(toggle)
            self.stackView.addArrangedSubview(toggleView)
            self.stackView.setCustomSpacing(32, after: toggleView)
        }

        if let primary {
            let primaryButtonView = viewForElement(primary)
            self.stackView.addArrangedSubview(primaryButtonView)
            self.stackView.setCustomSpacing(20, after: primaryButtonView)
        }

        if let secondary {
            let secondaryButtonView = viewForElement(secondary)
            self.stackView.addArrangedSubview(secondaryButtonView)
        }
    }

    private func viewForHero(_ hero: Hero) -> UIView {
        let heroView: UIView
        switch hero {
        case let .image(image, tintColor):
            heroView = UIImageView(image: image)
            heroView.contentMode = .center
            if let tintColor {
                heroView.tintColor = tintColor
            }
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

    private func viewForBulletPoint(
        _ bulletPoint: Body.BulletPoint,
        textColor: UIColor,
    ) -> UIView {
        let bulletContainer = UIView()
        bulletContainer.layoutMargins = UIEdgeInsets(hMargin: 24, vMargin: 0)

        let iconImageView = UIImageView()
        bulletContainer.addSubview(iconImageView)
        iconImageView.image = bulletPoint.icon
        iconImageView.tintColor = .Signal.secondaryLabel

        let bulletLabel = UILabel()
        bulletContainer.addSubview(bulletLabel)
        bulletLabel.font = .dynamicTypeSubheadline
        bulletLabel.textColor = textColor
        bulletLabel.numberOfLines = 0
        bulletLabel.textAlignment = .left
        bulletLabel.text = bulletPoint.text

        iconImageView.autoSetDimensions(to: .square(24))
        iconImageView.autoPinEdge(toSuperviewMargin: .leading)
        iconImageView.autoVCenterInSuperview()

        iconImageView.autoPinEdge(.trailing, to: .leading, of: bulletLabel, withOffset: -12)

        bulletLabel.autoPinEdges(toSuperviewMarginsExcludingEdge: .leading)

        return bulletContainer
    }

    private func viewForToggle(_ toggle: Body.Toggle) -> UIView {
        let titleLabel = UILabel()
        titleLabel.text = toggle.title
        titleLabel.font = .dynamicTypeSubheadline
        titleLabel.textAlignment = .natural
        titleLabel.numberOfLines = 0
        titleLabel.textColor = .Signal.label

        let toggleSwitch = UISwitch()
        toggleSwitch.setCompressionResistanceHigh()
        toggleSwitch.isOn = toggle.isOn
        toggleSwitch.addAction(
            UIAction { [weak self] action in
                guard
                    let toggle = self?.body.toggle,
                    let toggleSwitch = action.sender as? UISwitch
                else {
                    return
                }
                toggle.onValueChanged(toggleSwitch.isOn)
            },
            for: .valueChanged,
        )

        let pillView = PillView()
        pillView.backgroundColor = .Signal.tertiaryBackground
        pillView.layoutMargins = UIEdgeInsets(hMargin: 20, vMargin: 16)
        pillView.addSubview(titleLabel)
        pillView.addSubview(toggleSwitch)

        titleLabel.autoPinEdges(toSuperviewMarginsExcludingEdge: .trailing)

        toggleSwitch.autoPinEdge(.leading, to: .trailing, of: titleLabel, withOffset: 16, relation: .greaterThanOrEqual)
        toggleSwitch.autoPinEdge(toSuperviewMargin: .trailing)
        toggleSwitch.autoVCenterInSuperview()

        if let footer = toggle.footer {
            let footerLabel = UILabel()
            footerLabel.text = footer
            footerLabel.font = .dynamicTypeFootnote
            footerLabel.textAlignment = .natural
            footerLabel.numberOfLines = 0
            footerLabel.textColor = .Signal.secondaryLabel

            let pillAndFooterContainer = UIView()
            pillAndFooterContainer.addSubview(pillView)
            pillAndFooterContainer.addSubview(footerLabel)

            pillView.autoPinEdges(toSuperviewEdgesExcludingEdge: .bottom)
            footerLabel.autoPinEdge(.top, to: .bottom, of: pillView, withOffset: 8)
            footerLabel.autoPinEdgesToSuperviewEdges(
                with: UIEdgeInsets(hMargin: 20, vMargin: 0),
                excludingEdge: .top,
            )

            return pillAndFooterContainer
        } else {
            return pillView
        }
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

// MARK: -

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
#Preview("Body w/ bullets") {
    SheetPreviewViewController(sheet: HeroSheetViewController(
        hero: .image(UIImage(named: "sustainer-heart")!),
        title: nil,
        body: HeroSheetViewController.Body(
            textContent: .plain("As an independent nonprofit, Signal is committed to private messaging and calls. No ads, no trackers, no surveillance. Donate today to support Signal."),
            textAlignment: .left,
            textColor: .Signal.label,
            bulletPoints: [
                HeroSheetViewController.Body.BulletPoint(
                    icon: UIImage(named: "badge-multi")!,
                    text: "Get an optional badge on your profile when you donate",
                ),
                HeroSheetViewController.Body.BulletPoint(
                    icon: UIImage(named: "lock")!,
                    text: "Your privacy is our mission",
                ),
                HeroSheetViewController.Body.BulletPoint(
                    icon: UIImage(named: "heart")!,
                    text: "Signal is a 501c3 nonprofit. US donations are tax deductible.",
                ),
            ],
        ),
        primary: nil,
        secondary: nil,
    ))
}

@available(iOS 17, *)
#Preview("Body w/toggle-and-footer") {
    SheetPreviewViewController(sheet: HeroSheetViewController(
        hero: .image(UIImage(named: "toggle-32")!),
        title: "Feeding Boots the cat",
        body: HeroSheetViewController.Body(
            textContent: .plain(#"Give Boots extra dinner? He'd like you to know he's "extra hungry" tonight."#),
            toggle: HeroSheetViewController.Body.Toggle(
                title: "Extra dinner?",
                footer: "Side effects may include sleepiness and increased insistence that he receive extra food in the future.",
                isOn: true,
                onValueChanged: { enabled in
                    print(enabled ? "😸" : "😾")
                },
            ),
        ),
        primary: .button(.dismissing(title: "Order Up")),
        secondary: nil,
    ))
}

@available(iOS 17, *)
#Preview("Body w/long-text toggle") {
    SheetPreviewViewController(sheet: HeroSheetViewController(
        hero: .image(UIImage(named: "toggle-32")!),
        title: "Feeding Boots the Cat",
        body: HeroSheetViewController.Body(
            textContent: .plain(#"Give Boots extra dinner? He'd like you to know he's "extra hungry" tonight."#),
            toggle: HeroSheetViewController.Body.Toggle(
                title: "Give Boots extra dinner? Side effects may include sleepiness and increased insistence that he receive extra food in the future.",
                footer: nil,
                isOn: true,
                onValueChanged: { enabled in
                    print(enabled ? "😸" : "😾")
                },
            ),
        ),
        primary: .button(.dismissing(title: "Order Up")),
        secondary: nil,
    ))
}

@available(iOS 17, *)
#Preview("Body w/ link") {
    let bodyText: NSAttributedString = NSAttributedString.composed(of: [
        "Signal will never message you for your recovery key. Never respond to a chat pretending to be Signal. Never share your recovery key with anyone.",
        " ",
        CommonStrings.learnMore.styled(
            with: .link(.Support.phishingPrevention),
        ),
    ])

    SheetPreviewViewController(sheet: HeroSheetViewController(
        hero: .image(UIImage(named: "avatar_football")!),
        title: "Do Not Share Recovery Key",
        body: HeroSheetViewController.Body(textContent: .attributed(bodyText)),
        primary: .button(.dismissing(title: "Do Not Share Key")),
        secondary: .button(HeroSheetViewController.Button(
            title: LocalizationNotNeeded("Share Key"),
            style: .secondaryDestructive,
            action: .dismiss,
        )),
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
        body: HeroSheetViewController.Body(textContent: .plain(LocalizationNotNeeded("Continue transferring your account on your other device."))),
        primary: .hero(.animation(named: "circular_indeterminate", height: 60)),
        secondary: nil,
    ))
}

#endif
