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
        case image(UIImage, tintColor: UIColor? = nil, height: CGFloat? = nil)
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
            /// - Note
            /// Attributed-text bodies must embed their own font.
            case attributed(NSAttributedString)
        }

        public struct BulletPoint {
            public enum Style {
                case image(UIImage)
                case dot
                case dash
            }

            public let style: Style
            public let text: String

            public init(style: Style, text: String) {
                self.style = style
                self.text = text
            }

            public init(icon: UIImage, text: String) {
                self.init(style: .image(icon), text: text)
            }
        }

        public struct SelectableRow {
            public let icon: UIImage?
            public let title: String

            public init(icon: UIImage? = nil, title: String) {
                self.icon = icon
                self.title = title
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

        public enum Element {
            case text(
                TextContent,
                alignment: NSTextAlignment = .center,
                color: UIColor = .Signal.secondaryLabel,
            )
            case bullets(
                color: UIColor = .Signal.label,
                spacing: CGFloat = 12,
                hMargin: CGFloat = 24,
                _ points: [BulletPoint],
            )
            case toggle(Toggle)
            case selectableList(
                rows: [SelectableRow],
                initialSelectedIndex: Int?,
                onSelectionChanged: (Int) -> Void,
            )
            case customSpacing(CGFloat)
        }

        public let elements: [Element]
        /// Font used for elements (other than attributed text)
        public let font: UIFont

        public init(font: UIFont = .dynamicTypeSubheadline, _ elements: [Element]) {
            self.font = font
            self.elements = elements
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

    // Reference so `.selectableList` can adjust the enabled value after selection changes
    var primaryButton: UIButton?

    public init(
        hero: Hero,
        title: String?,
        body: String,
        primaryButton: Button?,
        secondaryButton: Button? = nil,
    ) {
        self.hero = hero
        self.titleText = title
        self.body = Body([.text(.plain(body))])
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

        // Reference so `.customSpacing` can adjust the spacing after it.
        var previousBodyView: UIView?

        for element in body.elements {
            switch element {
            case let .text(content, alignment, color):
                let textView = viewForText(content, alignment: alignment, color: color, font: body.font)
                self.stackView.addArrangedSubview(textView)
                self.stackView.setCustomSpacing(32, after: textView)
                previousBodyView = textView
            case let .bullets(color, spacing, hMargin, bulletPoints):
                for bulletPoint in bulletPoints {
                    let bulletView = viewForBulletPoint(bulletPoint, textColor: color, font: body.font, hMargin: hMargin)
                    self.stackView.addArrangedSubview(bulletView)
                    self.stackView.setCustomSpacing(spacing, after: bulletView)
                    previousBodyView = bulletView
                }
            case let .toggle(toggle):
                let toggleView = viewForToggle(toggle, font: body.font)
                self.stackView.addArrangedSubview(toggleView)
                self.stackView.setCustomSpacing(32, after: toggleView)
                previousBodyView = toggleView
            case let .selectableList(rows, initialSelectedIndex, onSelectionChanged):
                let listView = viewForSelectableList(
                    rows: rows,
                    initialSelectedIndex: initialSelectedIndex,
                    onSelectionChanged: { [weak self] index in
                        guard let self else { return }
                        reloadPrimaryButtonEnabled(updatedSelectedIndex: index)
                        onSelectionChanged(index)
                    },
                    font: body.font,
                )
                self.stackView.addArrangedSubview(listView)
                self.stackView.setCustomSpacing(32, after: listView)
                previousBodyView = listView
            case let .customSpacing(spacing):
                if let previousBodyView {
                    self.stackView.setCustomSpacing(spacing, after: previousBodyView)
                }
            }
        }

        if let primary {
            let primaryButtonView = viewForElement(primary)
            self.stackView.addArrangedSubview(primaryButtonView)
            self.stackView.setCustomSpacing(20, after: primaryButtonView)

            if let primaryButton = primaryButtonView as? UIButton {
                self.primaryButton = primaryButton
                reloadPrimaryButtonEnabled()
            }
        }

        if let secondary {
            let secondaryButtonView = viewForElement(secondary)
            self.stackView.addArrangedSubview(secondaryButtonView)
        }
    }

    private func reloadPrimaryButtonEnabled(updatedSelectedIndex: Int? = nil) {
        guard let primaryButton else { return }

        // Disable the primary button while any selectable list is still on
        // its initial selection. With no selectable list, the button is
        // always enabled.
        primaryButton.isEnabled = !body.elements.contains { element in
            guard case let .selectableList(_, initialSelectedIndex, _) = element else {
                return false
            }
            return (updatedSelectedIndex ?? initialSelectedIndex) == initialSelectedIndex
        }
    }

    private func viewForHero(_ hero: Hero) -> UIView {
        let heroView: UIView
        switch hero {
        case let .image(image, tintColor, height):
            let imageView = UIImageView(image: image)
            if let height {
                imageView.contentMode = .scaleAspectFit
                imageView.autoSetDimension(.height, toSize: height)
            } else {
                imageView.contentMode = .center
            }
            if let tintColor {
                imageView.tintColor = tintColor
            }
            heroView = imageView
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

    private func viewForText(
        _ content: Body.TextContent,
        alignment: NSTextAlignment,
        color: UIColor,
        font: UIFont,
    ) -> UIView {
        // Use a text view so embedded links in attributed bodies are tappable.
        let textView = LinkingTextView()
        switch content {
        case .plain(let text):
            textView.text = text
            textView.font = font
        case .attributed(let attributedText):
            textView.attributedText = attributedText
        }
        textView.textColor = color
        textView.textAlignment = alignment
        return textView
    }

    private func viewForBulletPoint(
        _ bulletPoint: Body.BulletPoint,
        textColor: UIColor,
        font: UIFont,
        hMargin: CGFloat,
    ) -> UIView {
        let bulletContainer = UIView()
        bulletContainer.layoutMargins = UIEdgeInsets(hMargin: hMargin, vMargin: 0)

        let bulletLabel = UILabel()
        bulletContainer.addSubview(bulletLabel)
        bulletLabel.font = font
        bulletLabel.textColor = textColor
        bulletLabel.numberOfLines = 0
        bulletLabel.textAlignment = .left
        bulletLabel.text = bulletPoint.text

        bulletLabel.autoPinEdges(toSuperviewMarginsExcludingEdge: .leading)

        switch bulletPoint.style {
        case .image(let icon):
            let iconImageView = UIImageView(image: icon)
            iconImageView.tintColor = .Signal.secondaryLabel
            bulletContainer.addSubview(iconImageView)

            iconImageView.autoSetDimensions(to: .square(24))
            iconImageView.autoPinEdge(toSuperviewMargin: .leading)
            iconImageView.autoVCenterInSuperview()
            iconImageView.autoPinEdge(.trailing, to: .leading, of: bulletLabel, withOffset: -12)

        case .dot:
            let dotLabel = UILabel()
            dotLabel.text = "•"
            dotLabel.font = bulletLabel.font
            dotLabel.textColor = textColor
            dotLabel.setContentHuggingHigh()
            dotLabel.setCompressionResistanceHigh()
            bulletContainer.addSubview(dotLabel)

            dotLabel.autoPinEdge(toSuperviewMargin: .leading)
            // Align the dot with the first line of text rather than centering.
            dotLabel.autoPinEdge(.top, to: .top, of: bulletLabel)
            dotLabel.autoPinEdge(.trailing, to: .leading, of: bulletLabel, withOffset: -8)

        case .dash:
            let dashView = UIView()
            dashView.backgroundColor = .Signal.tertiaryLabel
            dashView.layer.cornerRadius = 2
            bulletContainer.addSubview(dashView)

            dashView.autoSetDimensions(to: CGSize(width: 4, height: 14))
            dashView.autoPinEdge(toSuperviewMargin: .leading)
            dashView.autoVCenterInSuperview()
            dashView.autoPinEdge(.trailing, to: .leading, of: bulletLabel, withOffset: -8)
        }

        return bulletContainer
    }

    private func viewForToggle(_ toggle: Body.Toggle, font: UIFont) -> UIView {
        let titleLabel = UILabel()
        titleLabel.text = toggle.title
        titleLabel.font = font
        titleLabel.textAlignment = .natural
        titleLabel.numberOfLines = 0
        titleLabel.textColor = .Signal.label

        let toggleSwitch = UISwitch()
        toggleSwitch.setCompressionResistanceHigh()
        toggleSwitch.isOn = toggle.isOn
        toggleSwitch.addAction(
            UIAction { action in
                guard let toggleSwitch = action.sender as? UISwitch else {
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

    private func viewForSelectableList(
        rows: [Body.SelectableRow],
        initialSelectedIndex: Int?,
        onSelectionChanged: @escaping (Int) -> Void,
        font: UIFont,
    ) -> UIView {
        let container = UIView()
        container.backgroundColor = .Signal.tertiaryBackground
        container.layer.cornerRadius = OWSTableViewController2.cellRounding
        container.layer.masksToBounds = true

        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .fill
        container.addSubview(stack)
        stack.autoPinEdgesToSuperviewEdges()

        var rowViews: [SelectableListRowView] = []
        var selectedIndex = initialSelectedIndex

        for (index, row) in rows.enumerated() {
            let rowView = SelectableListRowView(
                row: row,
                isSelected: index == initialSelectedIndex,
                font: font,
            )
            rowView.onTap = { [weak rowView] in
                guard let rowView else { return }
                let previousIndex = selectedIndex
                selectedIndex = index
                onSelectionChanged(index)
                if let previousIndex, previousIndex != index, rowViews.indices.contains(previousIndex) {
                    rowViews[previousIndex].isSelected = false
                }
                rowView.isSelected = true
            }
            rowViews.append(rowView)
            stack.addArrangedSubview(rowView)

            if index != rows.count - 1 {
                stack.addHairline(with: .Signal.tertiaryFill)
            }
        }

        return container
    }

    private final class SelectableListRowView: UIControl {
        private let iconImageView = UIImageView()
        private let titleLabel = UILabel()
        private let checkmarkImageView = UIImageView(
            image: UIImage(systemName: "checkmark"),
        )

        var onTap: (() -> Void)?

        override var isSelected: Bool {
            didSet { checkmarkImageView.isHidden = !isSelected }
        }

        override var isHighlighted: Bool {
            didSet {
                UIView.animate(withDuration: 0.1) {
                    self.backgroundColor = self.isHighlighted
                        ? .Signal.tertiaryFill
                        : .clear
                }
            }
        }

        init(row: Body.SelectableRow, isSelected: Bool, font: UIFont) {
            super.init(frame: .zero)
            self.isSelected = isSelected

            iconImageView.image = row.icon
            iconImageView.tintColor = .Signal.label
            iconImageView.contentMode = .scaleAspectFit
            iconImageView.setContentHuggingHigh()
            iconImageView.setCompressionResistanceHigh()

            titleLabel.text = row.title
            titleLabel.font = font
            titleLabel.textColor = .Signal.label
            titleLabel.numberOfLines = 0

            checkmarkImageView.tintColor = .Signal.label
            checkmarkImageView.setContentHuggingHigh()
            checkmarkImageView.setCompressionResistanceHigh()
            checkmarkImageView.isHidden = !isSelected

            let stack = UIStackView(arrangedSubviews: [iconImageView, titleLabel, checkmarkImageView])
            stack.axis = .horizontal
            stack.alignment = .center
            stack.spacing = 12
            stack.isUserInteractionEnabled = false
            addSubview(stack)
            stack.autoPinEdgesToSuperviewEdges(with: .init(top: 14, leading: 16, bottom: 14, trailing: 16))
            iconImageView.autoSetDimensions(to: .square(20))

            addTarget(self, action: #selector(handleTap), for: .touchUpInside)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        @objc
        private func handleTap() {
            onTap?()
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
        body: HeroSheetViewController.Body([
            .text(
                .plain("As an independent nonprofit, Signal is committed to private messaging and calls. No ads, no trackers, no surveillance. Donate today to support Signal."),
                alignment: .left,
                color: .Signal.label,
            ),
            .bullets(spacing: 32, [
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
            ]),
        ]),
        primary: nil,
        secondary: nil,
    ))
}

@available(iOS 17, *)
#Preview("Body w/ text around bullets") {
    SheetPreviewViewController(sheet: HeroSheetViewController(
        hero: .image(UIImage(named: "sustainer-heart")!),
        title: nil,
        body: HeroSheetViewController.Body([
            .text(.plain("Signal is committed to private messaging and calls, because:"), alignment: .left, color: .Signal.label),
            .customSpacing(20),
            .bullets([
                HeroSheetViewController.Body.BulletPoint(style: .dash, text: "No ads, no trackers, no surveillance."),
                HeroSheetViewController.Body.BulletPoint(style: .dash, text: "Everything is end-to-end encrypted."),
            ]),
            .customSpacing(20),
            .text(.plain("Donate today to support Signal."), alignment: .left, color: .Signal.label),
        ]),
        primary: nil,
        secondary: nil,
    ))
}

@available(iOS 17, *)
#Preview("Body w/ dot bullets") {
    SheetPreviewViewController(sheet: HeroSheetViewController(
        hero: .image(UIImage(named: "sustainer-heart")!),
        title: nil,
        body: HeroSheetViewController.Body([
            .text(
                .plain("Signal is committed to private messaging and calls."),
                alignment: .left,
                color: .Signal.label,
            ),
            .bullets([
                HeroSheetViewController.Body.BulletPoint(style: .dot, text: "No ads, no trackers, no surveillance."),
                HeroSheetViewController.Body.BulletPoint(style: .dot, text: "An independent nonprofit whose mission is your privacy."),
                HeroSheetViewController.Body.BulletPoint(style: .dot, text: "Signal is a 501c3 nonprofit. US donations are tax deductible."),
            ]),
        ]),
        primary: nil,
        secondary: nil,
    ))
}

@available(iOS 17, *)
#Preview("Body w/toggle-and-footer") {
    SheetPreviewViewController(sheet: HeroSheetViewController(
        hero: .image(UIImage(named: "toggle-32")!),
        title: "Feeding Boots the cat",
        body: HeroSheetViewController.Body([
            .text(.plain(#"Give Boots extra dinner? He'd like you to know he's "extra hungry" tonight."#)),
            .toggle(HeroSheetViewController.Body.Toggle(
                title: "Extra dinner?",
                footer: "Side effects may include sleepiness and increased insistence that he receive extra food in the future.",
                isOn: true,
                onValueChanged: { enabled in
                    print(enabled ? "😸" : "😾")
                },
            )),
        ]),
        primary: .button(.dismissing(title: "Order Up")),
        secondary: nil,
    ))
}

@available(iOS 17, *)
#Preview("Body w/long-text toggle") {
    SheetPreviewViewController(sheet: HeroSheetViewController(
        hero: .image(UIImage(named: "toggle-32")!),
        title: "Feeding Boots the Cat",
        body: HeroSheetViewController.Body([
            .text(.plain(#"Give Boots extra dinner? He'd like you to know he's "extra hungry" tonight."#)),
            .toggle(HeroSheetViewController.Body.Toggle(
                title: "Give Boots extra dinner? Side effects may include sleepiness and increased insistence that he receive extra food in the future.",
                footer: nil,
                isOn: true,
                onValueChanged: { enabled in
                    print(enabled ? "😸" : "😾")
                },
            )),
        ]),
        primary: .button(.dismissing(title: "Order Up")),
        secondary: nil,
    ))
}

@available(iOS 17, *)
#Preview("Body w/ attributed") {
    let bodyText: NSAttributedString = NSAttributedString.composed(of: [
        "<bold>Signal will never message you</bold> for your recovery key. Never respond to a chat pretending to be Signal. Never share your recovery key with anyone.",
        " ",
        "<link>\(CommonStrings.learnMore)</link>",
    ]).styled(
        with: .font(.dynamicTypeSubheadline),
        .xmlRules([
            .style("bold", StringStyle(.font(.dynamicTypeSubheadline.bold()))),
            .style("link", StringStyle(.link(.Support.phishingPrevention))),
        ]),
    )

    SheetPreviewViewController(sheet: HeroSheetViewController(
        hero: .image(UIImage(named: "avatar_football")!),
        title: "Do Not Share Recovery Key",
        body: HeroSheetViewController.Body([.text(.attributed(bodyText))]),
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
        body: HeroSheetViewController.Body([.text(.plain(LocalizationNotNeeded("Continue transferring your account on your other device.")))]),
        primary: .hero(.animation(named: "circular_indeterminate", height: 60)),
        secondary: nil,
    ))
}

#endif
