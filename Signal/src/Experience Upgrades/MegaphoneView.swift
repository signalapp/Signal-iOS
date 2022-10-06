//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import Lottie

class MegaphoneView: UIView, ExperienceUpgradeView {
    let experienceUpgrade: ExperienceUpgrade

    enum ImageSize {
        case large, small
    }
    var imageSize: ImageSize = .small {
        willSet { assert(!hasPresented) }
    }
    var imageName: String? {
        didSet {
            if imageName != nil { image = nil }
        }
    }
    var image: UIImage? {
        didSet {
            if image != nil { imageName = nil }
        }
    }

    var animation: Animation?
    struct Animation {
        let name: String
        let backgroundImageName: String?
        let backgroundImageInset: CGFloat
        let speed: CGFloat
        let loopMode: LottieLoopMode
        let backgroundBehavior: LottieBackgroundBehavior
        let contentMode: UIView.ContentMode

        init(
            name: String,
            backgroundImageName: String? = nil,
            backgroundImageInset: CGFloat = 0,
            speed: CGFloat = 1,
            loopMode: LottieLoopMode = .playOnce,
            backgroundBehavior: LottieBackgroundBehavior = .forceFinish,
            contentMode: UIView.ContentMode = .scaleAspectFit
        ) {
            self.name = name
            self.speed = speed
            self.loopMode = loopMode
            self.backgroundBehavior = backgroundBehavior
            self.contentMode = contentMode
            self.backgroundImageName = backgroundImageName
            self.backgroundImageInset = backgroundImageInset
        }
    }

    enum ButtonOrientation {
        case horizontal, vertical
    }
    var buttonOrientation: ButtonOrientation = .horizontal {
        willSet { assert(!hasPresented) }
    }

    var titleText: String? {
        willSet { assert(!hasPresented) }
    }
    var bodyText: String? {
        willSet { assert(!hasPresented) }
    }

    struct Button {
        let title: String
        let action: () -> Void
    }

    private var buttons: [Button] = []
    func setButtons(primary: Button, secondary: Button? = nil) {
        assert(!hasPresented)

        if let secondary = secondary {
            buttons = [primary, secondary]
        } else {
            buttons = [primary]
        }
    }

    var isPresented: Bool { superview != nil }

    private let darkThemeBackgroundOverlay = UIView()
    private let stackView = UIStackView()
    init(experienceUpgrade: ExperienceUpgrade) {
        self.experienceUpgrade = experienceUpgrade

        super.init(frame: .zero)

        layer.cornerRadius = 12
        clipsToBounds = true

        if UIAccessibility.isReduceTransparencyEnabled {
            backgroundColor = .ows_blackAlpha80
        } else {
            let blurEffectView = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
            addSubview(blurEffectView)
            blurEffectView.autoPinEdgesToSuperviewEdges()
        }

        addSubview(darkThemeBackgroundOverlay)
        darkThemeBackgroundOverlay.autoPinEdgesToSuperviewEdges()
        darkThemeBackgroundOverlay.backgroundColor = UIColor.white.withAlphaComponent(0.10)

        stackView.axis = .vertical
        addSubview(stackView)
        stackView.autoPinEdgesToSuperviewEdges()

        NotificationCenter.default.addObserver(self, selector: #selector(applyTheme), name: .ThemeDidChange, object: nil)
        applyTheme()
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var hasPresented = false
    func present(fromViewController: UIViewController) {
        AssertIsOnMainThread()

        guard !hasPresented else { return owsFailDebug("can only present once") }

        guard titleText != nil, bodyText != nil, (imageName != nil || image != nil || animation != nil) else {
            return owsFailDebug("megaphone is not prepared for presentation")
        }

        // Top section

        let labelStack = createLabelStack()
        let imageContainer = createImageContainer()

        let topStackView = UIStackView(arrangedSubviews: [imageContainer, labelStack])

        switch imageSize {
        case .small:
            topStackView.axis = .horizontal
            topStackView.spacing = 8
            topStackView.isLayoutMarginsRelativeArrangement = true
            topStackView.layoutMargins = UIEdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
        case .large:
            topStackView.axis = .vertical
            topStackView.spacing = 10
            labelStack.isLayoutMarginsRelativeArrangement = true
            labelStack.layoutMargins = UIEdgeInsets(top: 0, leading: 12, bottom: 12, trailing: 12)
        }

        stackView.addArrangedSubview(topStackView)

        // Buttons

        if buttons.count > 0 {
            stackView.addArrangedSubview(createButtonsStack())
        } else {
            assert(buttons.isEmpty)
            addDismissButton()
        }

        fromViewController.view.addSubview(self)
        autoPinEdge(toSuperviewSafeArea: .leading, withInset: 8)
        autoPinEdge(toSuperviewSafeArea: .trailing, withInset: 8)
        autoPinEdge(toSuperviewSafeArea: .bottom, withInset: 8)

        animationView?.play()

        alpha = 0
        UIView.animate(withDuration: 0.2) {
            self.alpha = 1
        }

        hasPresented = true
    }

    @objc
    func applyTheme() {
        darkThemeBackgroundOverlay.isHidden = !Theme.isDarkThemeEnabled
    }

    @objc
    func tappedDismiss() {
        dismiss()
    }

    func dismiss(animated: Bool = true, completion: (() -> Void)? = nil) {
        UIView.animate(withDuration: animated ? 0.2 : 0, animations: {
            self.alpha = 0
        }) { _ in
            self.removeFromSuperview()
            completion?()
        }
    }

    func createLabelStack() -> UIStackView {
        let titleLabel = UILabel()
        titleLabel.numberOfLines = 0
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.font = UIFont.systemFont(ofSize: 17).ows_semibold
        titleLabel.textColor = Theme.darkThemePrimaryColor
        titleLabel.text = titleText

        let bodyLabel = UILabel()
        bodyLabel.numberOfLines = 0
        bodyLabel.lineBreakMode = .byWordWrapping
        bodyLabel.font = UIFont.systemFont(ofSize: 15)
        bodyLabel.textColor = Theme.darkThemeSecondaryTextAndIconColor
        bodyLabel.text = bodyText

        let topSpacer = UIView()
        let bottomSpacer = UIView()

        let labelStack = UIStackView(arrangedSubviews: [topSpacer, titleLabel, bodyLabel, bottomSpacer])
        labelStack.axis = .vertical

        topSpacer.autoMatch(.height, to: .height, of: bottomSpacer)

        return labelStack
    }

    private var animationView: AnimationView?
    func createImageContainer() -> UIView {
        let container: UIView

        if let image = { () -> UIImage? in
            if let imageName = imageName { return UIImage(named: imageName) }
            return image
        }() {
            container = UIView()
            let imageView = UIImageView()
            imageView.image = image
            imageView.contentMode = .scaleAspectFit
            container.addSubview(imageView)
            imageView.autoPinWidthToSuperview()
            imageView.autoPinEdge(toSuperviewEdge: .top)
        } else if let animation = animation {
            container = UIView()

            if let backgroundImageName = animation.backgroundImageName {
                let backgroundImageView = UIImageView()
                backgroundImageView.image = UIImage(named: backgroundImageName)
                backgroundImageView.contentMode = .scaleAspectFill
                container.addSubview(backgroundImageView)
                backgroundImageView.autoPinWidthToSuperview(withMargin: animation.backgroundImageInset)
                backgroundImageView.autoVCenterInSuperview()
            }

            let animationView = AnimationView(name: animation.name)
            self.animationView = animationView
            animationView.contentMode = animation.contentMode
            animationView.animationSpeed = animation.speed
            animationView.loopMode = animation.loopMode
            animationView.backgroundBehavior = animation.backgroundBehavior

            container.addSubview(animationView)
            animationView.autoPinEdgesToSuperviewEdges()
        } else {
            owsFailDebug("unexpectedly missing animation and image")
            container = UIView()
        }

        container.clipsToBounds = true

        switch imageSize {
        case .small:
            container.autoSetDimension(.width, toSize: 64)
            container.autoSetDimension(.height, toSize: 64, relation: .greaterThanOrEqual)
        case .large:
            container.autoSetDimension(.height, toSize: 128)
        }

        return container
    }

    func createButtonView(_ button: Button, font: UIFont = .systemFont(ofSize: 15)) -> OWSFlatButton {
        let buttonView = OWSFlatButton()

        buttonView.setTitle(title: button.title, font: font, titleColor: Theme.darkThemePrimaryColor)
        buttonView.setPressedBlock { button.action() }

        buttonView.autoSetDimension(.height, toSize: 44)

        return buttonView
    }

    func createButtonsStack() -> UIStackView {
        let buttonsStack = UIStackView()
        buttonsStack.addBackgroundView(withBackgroundColor: .ows_blackAlpha20)

        switch buttons.count {
        case 1:
            buttonsStack.addArrangedSubview(createButtonView(buttons[0]))
        case 2:
            var previousButton: UIView?
            for button in buttons {
                let buttonView = createButtonView(
                    button,
                    font: previousButton == nil ? UIFont.systemFont(ofSize: 15).ows_semibold : .systemFont(ofSize: 15)
                )

                switch buttonOrientation {
                case .vertical:
                    buttonsStack.addArrangedSubview(buttonView)
                case .horizontal:
                    buttonsStack.insertArrangedSubview(buttonView, at: 0)
                }

                previousButton?.autoMatch(.width, to: .width, of: buttonView)

                previousButton = buttonView
            }

            let dividerContainer = UIView()
            let divider = UIView()
            divider.backgroundColor = .ows_whiteAlpha20
            dividerContainer.addSubview(divider)
            buttonsStack.insertArrangedSubview(dividerContainer, at: 1)

            switch buttonOrientation {
            case .vertical:
                buttonsStack.axis = .vertical
                divider.autoSetDimension(.height, toSize: 1)
                divider.autoPinHeightToSuperview()
                divider.autoPinWidthToSuperview(withMargin: 12)
            case .horizontal:
                buttonsStack.axis = .horizontal
                divider.autoSetDimension(.width, toSize: 1)
                divider.autoPinWidthToSuperview()
                divider.autoPinHeightToSuperview(withMargin: 8)
            }
        default:
            owsFailDebug("only supports 1 or 2 buttons")
        }

        return buttonsStack
    }

    func addDismissButton() {
        let dismissButton = UIButton()
        dismissButton.setTemplateImageName("x-24", tintColor: Theme.darkThemePrimaryColor)
        dismissButton.addTarget(self, action: #selector(tappedDismiss), for: .touchUpInside)

        addSubview(dismissButton)

        dismissButton.autoSetDimensions(to: CGSize(square: 40))
        dismissButton.autoPinEdge(toSuperviewEdge: .trailing)
        dismissButton.autoPinEdge(toSuperviewEdge: .top)
    }

    func snoozeButton(fromViewController: UIViewController, snoozeTitle: String = MegaphoneStrings.remindMeLater, snoozeCopy: @escaping () -> String = { MegaphoneStrings.weWillRemindYouLater }) -> Button {
        return Button(title: snoozeTitle) { [weak self] in
            self?.markAsSnoozedWithSneakyTransaction()
            self?.dismiss {
                self?.presentToast(text: snoozeCopy(), fromViewController: fromViewController)
            }
        }
    }
}
