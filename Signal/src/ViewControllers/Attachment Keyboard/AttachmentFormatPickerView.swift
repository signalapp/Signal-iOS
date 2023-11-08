//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalCoreKit
import SignalServiceKit
import SignalUI
import UIKit

protocol AttachmentFormatPickerDelegate: AnyObject {
    func didTapPhotos()
    func didTapGif()
    func didTapFile()
    func didTapContact()
    func didTapLocation()
    func didTapPayment()
}

class AttachmentFormatPickerView: UIView {

    weak var attachmentFormatPickerDelegate: AttachmentFormatPickerDelegate?

    private let scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        return scrollView
    }()

    private lazy var contentView: UIStackView = {
        let buttons = AttachmentType.cases(isGroup: isGroup).map {
            let button = AttachmentTypeButton(attachmentType: $0)
            button.isVerticallyCompactAppearance = traitCollection.verticalSizeClass == .compact
            button.addTarget(self, action: #selector(didTapAttachmentButton), for: .touchUpInside)
            return button
        }
        let stackView = UIStackView(arrangedSubviews: buttons)
        stackView.spacing = 12
        stackView.axis = .horizontal
        stackView.alignment = .top
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()

    private let isGroup: Bool

    @objc
    private func didTapAttachmentButton(sender: Any) {
        guard
            let delegate = attachmentFormatPickerDelegate,
            let attachmentTypeButton = sender as? AttachmentTypeButton
        else {
            return
        }
        // Delay event handling a bit so that pressed state of the button is visible.
        DispatchQueue.main.async {
            switch attachmentTypeButton.attachmentType {
            case .photo:
                delegate.didTapPhotos()
            case .gif:
                delegate.didTapGif()
            case .file:
                delegate.didTapFile()
            case .payment:
                delegate.didTapPayment()
            case .contact:
                delegate.didTapContact()
            case .location:
                delegate.didTapLocation()
            }
        }
    }

    init(isGroup: Bool) {
        self.isGroup = isGroup

        super.init(frame: .zero)

        backgroundColor = .clear

        addSubview(scrollView)
        scrollView.autoPinEdgesToSuperviewEdges()

        scrollView.addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor)
        ])
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        let isLandscapeLayout = traitCollection.verticalSizeClass == .compact
        contentView.arrangedSubviews.forEach { subview in
            guard let button = subview as? AttachmentTypeButton else { return }
            button.isVerticallyCompactAppearance = isLandscapeLayout
        }
        invalidateIntrinsicContentSize()
    }

    override var intrinsicContentSize: CGSize {
        let height: CGFloat = traitCollection.verticalSizeClass == .compact ? 86 : 122
        return CGSize(width: UIView.noIntrinsicMetric, height: height)
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        // Dispatch async is needed for the subviews to have their final frames.
        DispatchQueue.main.async {
            self.updateScrollViewContentInsets()
        }
    }

    private func updateScrollViewContentInsets() {
        // Center button row horizontally and vertically in the scroll view.
        let scrollViewSize = scrollView.frame.size
        let contentSize = contentView.bounds.size
        guard scrollViewSize.isNonEmpty, contentSize.isNonEmpty else { return }
        let horizontalInset = max(OWSTableViewController2.defaultHOuterMargin, 0.5 * (scrollViewSize.width - contentSize.width))
        let verticalInset = max(0, 0.5 * (scrollViewSize.height - contentSize.height))
        let contentInset = UIEdgeInsets(hMargin: horizontalInset, vMargin: verticalInset)
        guard scrollView.contentInset != contentInset else { return }
        scrollView.contentInset = contentInset
        scrollView.contentOffset = CGPoint(x: -contentInset.leading, y: -contentInset.top)
    }

    // Set initial state for all buttons - get them ready to be animated in.
    func prepareForPresentation() {
        let buttons = contentView.arrangedSubviews
        guard !buttons.isEmpty else { return }

        UIView.performWithoutAnimation {
            buttons.forEach { button in
                button.alpha = 0
                button.transform = .scale(0.5)
            }
        }
    }

    func performPresentationAnimation() {
        let buttons = contentView.arrangedSubviews
        guard !buttons.isEmpty else { return }

        // Chain animations for buttons.
        let delay = 1 / CGFloat(buttons.count)
        let animator = UIViewPropertyAnimator(duration: 0.5, springDamping: 1, springResponse: 0.2)
        for (index, button) in buttons.enumerated() {
            animator.addAnimations({
                button.alpha = 1
                button.transform = .identity
            }, delayFactor: CGFloat(index) * delay)
        }
        animator.startAnimation()
    }

    private enum AttachmentType: String, CaseIterable, Dependencies {
        case photo
        case gif
        case file
        case contact
        case location
        case payment

        private static var contactCases: [AttachmentType] {
            if payments.shouldShowPaymentsUI {
                return allCases
            } else {
                return everythingExceptPayments
            }
        }

        private static var groupCases: [AttachmentType] {
            everythingExceptPayments
        }

        private static var everythingExceptPayments: [AttachmentType] {
            return allCases.filter { (value: AttachmentType) in
                value != .payment
            }
        }

        static func cases(isGroup: Bool) -> [AttachmentType] {
            return isGroup ? groupCases : contactCases
        }
    }

    private class AttachmentTypeButton: UIControl {

        private class DimmablePillView: PillView {

            private let dimmerView: UIView = {
                let view = UIView()
                view.backgroundColor = Theme.isDarkThemeEnabled ? .ows_whiteAlpha10 : .ows_blackAlpha10
                view.alpha = 0
                return view
            }()

            // Implicitly animatable.
            var isDimmed: Bool = false {
                didSet {
                    dimmerView.alpha = isDimmed ? 1 : 0
                }
            }

            override init(frame: CGRect) {
                super.init(frame: frame)
                addSubview(dimmerView)
            }

            required init?(coder aDecoder: NSCoder) {
                fatalError("init(coder:) has not been implemented")
            }

            override func layoutSubviews() {
                super.layoutSubviews()
                dimmerView.frame = bounds
            }
        }

        let attachmentType: AttachmentType

        var isVerticallyCompactAppearance = false {
            didSet {
                imageViewPillBoxHeightConstraint.constant = isVerticallyCompactAppearance ? 40 : 50
            }
        }

        private let imageViewPillBox: DimmablePillView = {
            let pillView = DimmablePillView()
            pillView.isUserInteractionEnabled = false
            pillView.backgroundColor = Theme.isDarkThemeEnabled ? UIColor(white: 1, alpha: 0.16) : UIColor(white: 0, alpha: 0.08)
            return pillView
        }()

        private lazy var imageViewPillBoxHeightConstraint: NSLayoutConstraint = {
            imageViewPillBox.heightAnchor.constraint(equalToConstant: 50)
        }()

        private let iconImageView: UIImageView = {
            let imageView = UIImageView()
            imageView.contentMode = .center
            imageView.tintColor = Theme.isDarkThemeEnabled ? .white : .black
            return imageView
        }()

        private let textLabel: UILabel = {
            let label = UILabel()
            label.font = .dynamicTypeFootnoteClamped.medium()
            label.textColor = Theme.secondaryTextAndIconColor
            label.textAlignment = .center
            label.numberOfLines = 2
            label.adjustsFontSizeToFitWidth = true
            label.lineBreakMode = .byCharWrapping
            return label
        }()

        init(attachmentType: AttachmentType) {
            self.attachmentType = attachmentType

            super.init(frame: .zero)

            translatesAutoresizingMaskIntoConstraints = false

            imageViewPillBox.addSubview(iconImageView)
            iconImageView.autoPinEdgesToSuperviewEdges()

            addSubview(imageViewPillBox)
            NSLayoutConstraint.activate([
                imageViewPillBox.widthAnchor.constraint(equalToConstant: 76),
                imageViewPillBoxHeightConstraint
            ])
            imageViewPillBox.autoPinEdges(toSuperviewEdgesExcludingEdge: .bottom)

            addSubview(textLabel)
            textLabel.autoPinEdge(.top, to: .bottom, of: imageViewPillBox, withOffset: 8)
            textLabel.autoPinEdges(toSuperviewEdgesExcludingEdge: .top)

            configure()
        }

        override var isHighlighted: Bool {
            didSet {
                setIsPressed(isHighlighted, animated: window != nil)
            }
        }

        private var _isPressed = false

        private var isPressed: Bool {
            get { _isPressed }
            set { setIsPressed(newValue, animated: false) }
        }

        private func setIsPressed(_ isPressed: Bool, animated: Bool) {
            _isPressed = isPressed

            let changes = {
                self.imageViewPillBox.isDimmed = isPressed
                self.imageViewPillBox.transform = isPressed ? .scale(0.9) : .identity
            }
            guard animated else {
                changes()
                return
            }

            let animator = UIViewPropertyAnimator(duration: 0.15, springDamping: 0.64, springResponse: 0.25)
            animator.addAnimations(changes)
            animator.startAnimation()
        }

        @available(*, unavailable, message: "Unimplemented")
        required public init?(coder aDecoder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        private func configure() {
            let imageName: String
            let text: String

            switch attachmentType {
            case .photo:
                text = OWSLocalizedString("ATTACHMENT_KEYBOARD_PHOTOS", comment: "A button to open the photo picker from the Attachment Keyboard")
                imageName = "album-tilt-28"
            case .contact:
                text = OWSLocalizedString("ATTACHMENT_KEYBOARD_CONTACT", comment: "A button to select a contact from the Attachment Keyboard")
                imageName = "person-circle-28"
            case .file:
                text = OWSLocalizedString("ATTACHMENT_KEYBOARD_FILE", comment: "A button to select a file from the Attachment Keyboard")
                imageName = "file-28"
            case .gif:
                text = OWSLocalizedString("ATTACHMENT_KEYBOARD_GIF", comment: "A button to select a GIF from the Attachment Keyboard")
                imageName = "gif-28"
            case .location:
                text = OWSLocalizedString("ATTACHMENT_KEYBOARD_LOCATION", comment: "A button to select a location from the Attachment Keyboard")
                imageName = "location-28"
            case .payment:
                text = OWSLocalizedString("ATTACHMENT_KEYBOARD_PAYMENT", comment: "A button to select a payment from the Attachment Keyboard")
                imageName = "payment-28"
            }

            textLabel.text = text
            iconImageView.image = UIImage(imageLiteralResourceName: imageName)
            accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "format-\(attachmentType.rawValue)")
        }
    }

}
