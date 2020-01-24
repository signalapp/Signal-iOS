//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

class MegaphoneView: UIView, ExperienceUpgradeView {
    let experienceUpgrade: ExperienceUpgrade

    enum ImageSize {
        case large, small
    }
    var imageSize: ImageSize = .small {
        willSet { assert(!hasPresented) }
    }
    var imageName: String?

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

    var didDismiss: (() -> Void)?

    struct Button {
        let title: String
        let action: () -> Void
    }

    private var buttons: [Button] = []
    func setButtons(primary: Button, secondary: Button) {
        assert(!hasPresented)

        buttons = [primary, secondary]
    }

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

        stackView.axis = .vertical
        addSubview(stackView)
        stackView.autoPinEdgesToSuperviewEdges()
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var hasPresented = false
    func present(fromViewController: UIViewController) {
        AssertIsOnMainThread()

        guard !hasPresented else { return owsFailDebug("can only present once") }

        guard let imageName = imageName, titleText != nil, bodyText != nil else {
            return owsFailDebug("megaphone is not prepared for presentation")
        }

        // Top section

        let labelStack = createLabelStack()
        let imageView = createImageView(imageName: imageName)

        let topStackView = UIStackView(arrangedSubviews: [imageView, labelStack])

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

        if buttons.count == 2 {
            stackView.addArrangedSubview(createButtonsStack())
        } else {
            assert(buttons.isEmpty)
            addDismissButton()
        }

        fromViewController.view.addSubview(self)
        autoPinWidthToSuperview(withMargin: 8)
        autoPinEdge(toSuperviewSafeArea: .bottom, withInset: 8)

        alpha = 0
        UIView.animate(withDuration: 0.2) {
            self.alpha = 1
        }

        hasPresented = true
    }

    @objc func dismiss(animated: Bool = true, completionHandler: (() -> Void)? = nil) {
        UIView.animate(withDuration: animated ? 0.2 : 0, animations: {
            self.alpha = 0
        }) { _ in
            self.removeFromSuperview()
            self.didDismiss?()
            completionHandler?()
        }
    }

    func createLabelStack() -> UIStackView {
        let titleLabel = UILabel()
        titleLabel.numberOfLines = 0
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.font = UIFont.systemFont(ofSize: 17).ows_semibold()
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

    func createImageView(imageName: String) -> UIImageView {
        let imageView = UIImageView()
        imageView.clipsToBounds = true
        imageView.image = UIImage(named: imageName)
        imageView.contentMode = .scaleAspectFit

        switch imageSize {
        case .small:
            imageView.autoSetDimensions(to: CGSize(square: 64))
        case .large:
            imageView.autoSetDimension(.height, toSize: 128)
        }

        return imageView
    }

    func createButtonsStack() -> UIStackView {
        assert(buttons.count == 2)

        let buttonsStack = UIStackView()
        buttonsStack.addBackgroundView(withBackgroundColor: .ows_blackAlpha20)

        var previousButton: UIView?
        for button in buttons {
            let buttonView = OWSFlatButton()

            let font: UIFont = previousButton == nil ? UIFont.systemFont(ofSize: 15).ows_semibold() : .systemFont(ofSize: 15)

            buttonView.setTitle(title: button.title, font: font, titleColor: Theme.darkThemePrimaryColor)
            buttonView.setPressedBlock {
                button.action()
            }

            switch buttonOrientation {
            case .vertical:
                buttonsStack.addArrangedSubview(buttonView)
            case .horizontal:
                buttonsStack.insertArrangedSubview(buttonView, at: 0)
            }

            buttonView.autoSetDimension(.height, toSize: 44)
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

        return buttonsStack
    }

    func addDismissButton() {
        let dismissButton = UIButton()
        dismissButton.setTemplateImageName("x-24", tintColor: Theme.darkThemePrimaryColor)
        dismissButton.addTarget(self, action: #selector(dismiss), for: .touchUpInside)

        addSubview(dismissButton)

        dismissButton.autoSetDimensions(to: CGSize(square: 40))
        dismissButton.autoPinEdge(toSuperviewEdge: .trailing)
        dismissButton.autoPinEdge(toSuperviewEdge: .top)
    }

    func snoozeButton(fromViewController: UIViewController) -> Button {
        return Button(title: MegaphoneStrings.remindMeLater) { [weak self] in
            self?.markAsSnoozed()
            self?.dismiss {
                self?.presentToast(text: MegaphoneStrings.weWillRemindYouLater, fromViewController: fromViewController)
            }
        }
    }
}
