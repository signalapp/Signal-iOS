//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Lottie
import SignalServiceKit
import SignalUI

@MainActor
class Megaphone {
    struct Button {
        let title: String
        let action: () -> Void
    }

    let experienceUpgrade: ExperienceUpgrade
    var image: UIImage?
    var imageContentMode: UIView.ContentMode = .scaleAspectFit
    var titleText: String?
    var bodyText: String?
    var buttons: [Button] = []

    init(experienceUpgrade: ExperienceUpgrade) {
        self.experienceUpgrade = experienceUpgrade
    }

    func buildView() -> MegaphoneView {
        guard let titleText, let bodyText else {
            owsFail("Megaphone missing title or body text!")
        }
        guard (1...2).contains(buttons.count) else {
            owsFail("Megaphone must have 1 or 2 buttons!")
        }

        return MegaphoneView(
            image: image,
            imageContentMode: imageContentMode,
            titleText: titleText,
            bodyText: bodyText,
            buttons: buttons,
        )
    }

    func snoozeButton(
        fromViewController: UIViewController,
        snoozeTitle: String,
    ) -> Button {
        return Button(title: snoozeTitle) { [weak self, weak fromViewController] in
            guard let self, let fromViewController else { return }

            markAsSnoozedWithSneakyTransaction()
            fromViewController.presentToast(text: MegaphoneStrings.weWillRemindYouLater)
        }
    }

    // MARK: -

    func markAsSnoozedWithSneakyTransaction() {
        let db = DependenciesBridge.shared.db
        let experienceUpgradeStore = ExperienceUpgradeStore()

        db.write { tx in
            experienceUpgradeStore.markAsSnoozed(
                experienceUpgrade: experienceUpgrade,
                tx: tx,
            )
        }

        NotificationCenter.default.post(name: .megaphoneStateDidChange, object: nil)
    }

    func markAsCompleteWithSneakyTransaction() {
        let db = DependenciesBridge.shared.db
        let experienceUpgradeStore = ExperienceUpgradeStore()

        db.write { tx in
            experienceUpgradeStore.markAsComplete(
                experienceUpgrade: experienceUpgrade,
                tx: tx,
            )
        }

        NotificationCenter.default.post(name: .megaphoneStateDidChange, object: nil)
    }
}

// MARK: -

class MegaphoneView: UIView {
    private let image: UIImage?
    private let imageContentMode: UIView.ContentMode
    private let titleText: String
    private let bodyText: String
    private let buttons: [Megaphone.Button]

    private let stackView = UIStackView()

    init(
        image: UIImage?,
        imageContentMode: UIView.ContentMode,
        titleText: String,
        bodyText: String,
        buttons: [Megaphone.Button],
    ) {
        self.image = image
        self.imageContentMode = imageContentMode
        self.titleText = titleText
        self.bodyText = bodyText
        self.buttons = buttons

        super.init(frame: .zero)

        layer.cornerRadius = 12
        clipsToBounds = true

        let blurEffectView = UIVisualEffectView(effect: UIBlurEffect(style: .regular))
        blurEffectView.overrideUserInterfaceStyle = .dark
        addSubview(blurEffectView)
        blurEffectView.autoPinEdgesToSuperviewEdges()

        // We want this background to change color with dark / light interface, but not the rest of the UI.
        let darkThemeBackgroundOverlay = UIView()
        darkThemeBackgroundOverlay.backgroundColor = UIColor(light: .clear, dark: .white.withAlphaComponent(0.1))
        addSubview(darkThemeBackgroundOverlay)
        darkThemeBackgroundOverlay.autoPinEdgesToSuperviewEdges()

        stackView.overrideUserInterfaceStyle = .dark
        stackView.axis = .vertical
        addSubview(stackView)
        stackView.autoPinEdgesToSuperviewEdges()
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: -

    func present(fromViewController: UIViewController) {
        AssertIsOnMainThread()

        let labelStack = createLabelStack()

        let topStackSubviews: [UIView]
        if let image {
            topStackSubviews = [createImageContainer(image: image), labelStack]
        } else {
            topStackSubviews = [labelStack]
        }

        let topStackView = UIStackView(arrangedSubviews: topStackSubviews)
        topStackView.axis = .horizontal
        topStackView.spacing = 8
        topStackView.isLayoutMarginsRelativeArrangement = true
        topStackView.layoutMargins = UIEdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)

        stackView.addArrangedSubview(topStackView)
        stackView.addArrangedSubview(createButtonsStack())

        fromViewController.view.addSubview(self)
        autoPinEdge(toSuperviewSafeArea: .leading, withInset: 8)
        autoPinEdge(toSuperviewSafeArea: .trailing, withInset: 8)
        autoPinEdge(toSuperviewSafeArea: .bottom, withInset: 8)

        alpha = 0
        UIView.animate(withDuration: 0.2) {
            self.alpha = 1
        }
    }

    func dismiss() {
        removeFromSuperview()
    }

    // MARK: -

    private func createLabelStack() -> UIStackView {
        let titleLabel = UILabel()
        titleLabel.numberOfLines = 0
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.font = .semiboldFont(ofSize: 17)
        titleLabel.textColor = .Signal.label
        titleLabel.text = titleText

        let bodyLabel = UILabel()
        bodyLabel.numberOfLines = 0
        bodyLabel.lineBreakMode = .byWordWrapping
        bodyLabel.font = .systemFont(ofSize: 15)
        bodyLabel.textColor = .Signal.secondaryLabel
        bodyLabel.text = bodyText

        let topSpacer = UIView()
        let bottomSpacer = UIView()

        let labelStack = UIStackView(arrangedSubviews: [topSpacer, titleLabel, bodyLabel, bottomSpacer])
        labelStack.axis = .vertical

        topSpacer.autoMatch(.height, to: .height, of: bottomSpacer)

        return labelStack
    }

    private func createImageContainer(image: UIImage) -> UIView {
        let container = UIView()
        let imageView = UIImageView()
        imageView.image = image
        imageView.contentMode = self.imageContentMode
        container.addSubview(imageView)
        imageView.autoPinWidthToSuperview()
        imageView.autoPinToSquareAspectRatio()
        imageView.autoVCenterInSuperview()

        container.autoSetDimension(.width, toSize: 64)
        container.autoSetDimension(.height, toSize: 64, relation: .greaterThanOrEqual)

        return container
    }

    private func createButtonView(
        _ button: Megaphone.Button,
        font: UIFont = .regularFont(ofSize: 15),
    ) -> UIButton {
        var buttonConfig = UIButton.Configuration.plain()
        buttonConfig.contentInsets = .zero
        buttonConfig.cornerStyle = .fixed
        buttonConfig.background.cornerRadius = 0
        buttonConfig.title = button.title
        buttonConfig.attributedTitle?.font = font
        buttonConfig.baseForegroundColor = .Signal.label

        let uiButton = UIButton(
            configuration: buttonConfig,
            primaryAction: UIAction { _ in button.action() },
        )
        uiButton.autoSetDimension(.height, toSize: 44)

        return uiButton
    }

    private func createButtonsStack() -> UIStackView {
        let buttonsStack = UIStackView()
        buttonsStack.addBackgroundView(withBackgroundColor: .ows_blackAlpha20)

        switch buttons.count {
        case 1:
            buttonsStack.addArrangedSubview(createButtonView(
                buttons[0],
                font: .regularFont(ofSize: 15),
            ))
        case 2:
            var previousButton: UIView?
            for button in buttons {
                let buttonView = createButtonView(
                    button,
                    font: previousButton == nil ? .semiboldFont(ofSize: 15) : .regularFont(ofSize: 15),
                )
                buttonsStack.insertArrangedSubview(buttonView, at: 0)

                previousButton?.autoMatch(.width, to: .width, of: buttonView)
                previousButton = buttonView
            }

            let dividerContainer = UIView()
            let divider = UIView()
            divider.backgroundColor = .ows_whiteAlpha20
            dividerContainer.addSubview(divider)
            buttonsStack.insertArrangedSubview(dividerContainer, at: 1)
            buttonsStack.axis = .horizontal
            divider.autoSetDimension(.width, toSize: 1)
            divider.autoPinWidthToSuperview()
            divider.autoPinHeightToSuperview(withMargin: 8)
        default:
            owsFail("Megaphones must have one or two buttons!")
        }

        return buttonsStack
    }
}
