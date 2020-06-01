//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

protocol EmojiPickerSectionToolbarDelegate: class {
    func emojiPickerSectionToolbar(_ sectionToolbar: EmojiPickerSectionToolbar, didSelectSection: Int)
    func emojiPickerSectionToolbarShouldShowRecentsSection(_ sectionToolbar: EmojiPickerSectionToolbar) -> Bool
}

class EmojiPickerSectionToolbar: UIView {
    private let toolbar = UIToolbar()
    private var blurEffectView: UIVisualEffectView?
    private var buttons = [UIButton]()

    private weak var delegate: EmojiPickerSectionToolbarDelegate?

    init(delegate: EmojiPickerSectionToolbarDelegate) {
        self.delegate = delegate

        super.init(frame: .zero)

        addSubview(toolbar)
        toolbar.autoPinEdge(toSuperviewSafeArea: .bottom)
        toolbar.autoPinWidthToSuperview()
        toolbar.autoPinEdge(toSuperviewSafeArea: .top)
        toolbar.tintColor = Theme.primaryIconColor

        if UIAccessibility.isReduceTransparencyEnabled {
            blurEffectView?.isHidden = true
            let color = Theme.navbarBackgroundColor
            let backgroundImage = UIImage(color: color)
            toolbar.setBackgroundImage(backgroundImage, forToolbarPosition: .any, barMetrics: .default)
        } else {
            // Make navbar more translucent than default. Navbars remove alpha from any assigned backgroundColor, so
            // to achieve transparency, we have to assign a transparent image.
            toolbar.setBackgroundImage(UIImage(color: .clear), forToolbarPosition: .any, barMetrics: .default)

            let blurEffect = Theme.barBlurEffect

            let blurEffectView: UIVisualEffectView = {
                if let existingBlurEffectView = self.blurEffectView {
                    existingBlurEffectView.isHidden = false
                    return existingBlurEffectView
                }

                let blurEffectView = UIVisualEffectView()
                blurEffectView.isUserInteractionEnabled = false

                self.blurEffectView = blurEffectView
                insertSubview(blurEffectView, at: 0)

                blurEffectView.autoPinEdgesToSuperviewEdges()

                return blurEffectView
            }()

            blurEffectView.effect = blurEffect

            // remove hairline below bar.
            toolbar.setShadowImage(UIImage(), forToolbarPosition: .any)

            // On iOS11, despite inserting the blur at 0, other views are later inserted into the navbar behind the blur,
            // so we have to set a zindex to avoid obscuring navbar title/buttons.
            blurEffectView.layer.zPosition = -1
        }

        buttons = [
            createSectionButton(icon: .emojiSmiley),
            createSectionButton(icon: .emojiAnimal),
            createSectionButton(icon: .emojiFood),
            createSectionButton(icon: .emojiActivity),
            createSectionButton(icon: .emojiTravel),
            createSectionButton(icon: .emojiObject),
            createSectionButton(icon: .emojiSymbol),
            createSectionButton(icon: .emojiFlag)
        ]

        if delegate.emojiPickerSectionToolbarShouldShowRecentsSection(self) == true {
            buttons.insert(createSectionButton(icon: .emojiRecent), at: 0)
        }

        toolbar.items = Array(
            buttons
                .map { [UIBarButtonItem(customView: $0)] }
                .joined(separator: [UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)])
        )

        setSelectedSection(0)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func createSectionButton(icon: ThemeIcon) -> UIButton {
        let button = UIButton()
        button.setImage(Theme.iconImage(icon), for: .normal)

        let selectedBackgroundColor = UIAccessibility.isReduceTransparencyEnabled
            ? (Theme.isDarkThemeEnabled ? UIColor.ows_gray75 : UIColor.ows_gray05)
            : Theme.backgroundColor

        button.setBackgroundImage(UIImage(color: selectedBackgroundColor), for: .selected)

        button.autoSetDimensions(to: CGSize(square: 30))
        button.layer.cornerRadius = 15
        button.clipsToBounds = true

        button.addTarget(self, action: #selector(didSelectSection), for: .touchUpInside)

        return button
    }

    @objc func didSelectSection(sender: UIButton) {
        guard let selectedSection = buttons.firstIndex(of: sender) else {
            return owsFailDebug("Selectetd unexpected button")
        }

        setSelectedSection(selectedSection)

        delegate?.emojiPickerSectionToolbar(self, didSelectSection: selectedSection)
    }

    func setSelectedSection(_ section: Int) {
        buttons.forEach { $0.isSelected = false }
        buttons[safe: section]?.isSelected = true
    }
}
