//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

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
    func didTapPoll()
}

class AttachmentFormatPickerView: UIView {

    weak var attachmentFormatPickerDelegate: AttachmentFormatPickerDelegate?

    var shouldLeaveSpaceForPermissions: Bool = false {
        didSet {
            self.invalidateIntrinsicContentSize()
        }
    }

    private let scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        return scrollView
    }()

    private lazy var contentView: UIStackView = {
        let subviews = AttachmentType.cases(isGroup: isGroup).map { attachmentType in
            let subview = AttachmentTypeView(attachmentType: attachmentType)
            subview.isVerticallyCompactAppearance = traitCollection.verticalSizeClass == .compact
            subview.button.addAction(
                UIAction(handler: { [weak self] _ in
                    self?.didTapAttachmentButton(attachmentType: attachmentType)
                }),
                for: .touchUpInside,
            )
            return subview
        }
        let stackView = UIStackView(arrangedSubviews: subviews)
        stackView.spacing = 12
        stackView.axis = .horizontal
        stackView.alignment = .top
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()

    private let isGroup: Bool

    private func didTapAttachmentButton(attachmentType: AttachmentType) {
        guard let delegate = attachmentFormatPickerDelegate else { return }

        // Delay event handling a bit so that pressed state of the button is visible.
        DispatchQueue.main.async {
            switch attachmentType {
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
            case .poll:
                delegate.didTapPoll()
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
            contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
        ])
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        let isLandscapeLayout = traitCollection.verticalSizeClass == .compact
        contentView.arrangedSubviews.forEach { subview in
            guard let view = subview as? AttachmentTypeView else { return }
            view.isVerticallyCompactAppearance = isLandscapeLayout
        }
        invalidateIntrinsicContentSize()
    }

    override var intrinsicContentSize: CGSize {
        let isVerticallyCompact = traitCollection.verticalSizeClass == .compact
        let height: CGFloat =
            switch (isVerticallyCompact, shouldLeaveSpaceForPermissions) {
            case (false, false): 122
            case (false, true): 100
            case (true, false): 86
            case (true, true): 76
            }
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

    private enum AttachmentType: String, CaseIterable {
        case photo
        case gif
        case file
        case poll
        case contact
        case location
        case payment

        private static var contactCases: [AttachmentType] {
            var casesToExclude: [AttachmentType] = [.poll]
            if !SSKEnvironment.shared.paymentsHelperRef.arePaymentsEnabled {
                casesToExclude.append(.payment)
            }

            return cases(except: casesToExclude)
        }

        private static var groupCases: [AttachmentType] {
            if !RemoteConfig.current.pollCreate {
                return cases(except: [.payment, .poll])
            }
            return cases(except: [.payment])
        }

        private static func cases(except: [AttachmentType]) -> [AttachmentType] {
            let showGifSearch = RemoteConfig.current.enableGifSearch
            return allCases.filter { (value: AttachmentType) in
                if value == .gif, showGifSearch.negated { return false }
                return except.contains(value).negated
            }
        }

        static func cases(isGroup: Bool) -> [AttachmentType] {
            return isGroup ? groupCases : contactCases
        }
    }

    private class AttachmentTypeView: UIView {

        @available(iOS, deprecated: 26.0)
        private class ShrinkingOnTapButton: UIButton {

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
                    self.transform = isPressed ? .scale(0.9) : .identity
                }
                guard animated else {
                    changes()
                    return
                }

                let animator = UIViewPropertyAnimator(duration: 0.15, springDamping: 0.64, springResponse: 0.25)
                animator.addAnimations(changes)
                animator.startAnimation()
            }
        }

        let button: UIButton = {
            let button: UIButton
            if #available(iOS 26, *), BuildFlags.iOS26SDKIsAvailable {
#if compiler(>=6.2)
                button = UIButton(configuration: .glass())
#else
                button = UIButton(configuration: .plain())
#endif
            } else {
                button = ShrinkingOnTapButton(configuration: .gray())
                button.configuration?.background.backgroundColorTransformer = UIConfigurationColorTransformer { [weak button] _ in
                    let baseColor = UIColor.Signal.secondaryFill
                    guard let button, button.isHighlighted else {
                        return baseColor
                    }
                    // Tinted color for "highlighted" state.
                    let tintColor = button.traitCollection.userInterfaceStyle == .dark ? UIColor.white : UIColor.black
                    return baseColor.blended(with: tintColor, alpha: 0.1)
                }
            }
            button.configuration?.baseForegroundColor = .Signal.label
            button.configuration?.cornerStyle = .capsule
            return button
        }()

        let attachmentType: AttachmentType

        var isVerticallyCompactAppearance = false {
            didSet {
                buttonHeightConstraint.constant = isVerticallyCompactAppearance ? 40 : 50
            }
        }

        private lazy var buttonHeightConstraint: NSLayoutConstraint = {
            button.heightAnchor.constraint(equalToConstant: 50)
        }()

        private let textLabel: UILabel = {
            let label = UILabel()
            label.font = .dynamicTypeFootnoteClamped.medium()
            if #available(iOS 26, *), BuildFlags.iOS26SDKIsAvailable {
                label.textColor = .Signal.label
            } else {
                label.textColor = .Signal.secondaryLabel
            }
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

            addSubview(button)
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: 76),
                buttonHeightConstraint,
            ])
            button.autoPinEdges(toSuperviewEdgesExcludingEdge: .bottom)

            addSubview(textLabel)
            textLabel.autoPinEdge(.top, to: .bottom, of: button, withOffset: 8)
            textLabel.autoPinEdges(toSuperviewEdgesExcludingEdge: .top)

            configure()
        }

        @available(*, unavailable, message: "Unimplemented")
        required init?(coder aDecoder: NSCoder) {
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
            case .poll:
                text = OWSLocalizedString("ATTACHMENT_KEYBOARD_POLL", comment: "A button to select a poll from the Attachment Keyboard")
                imageName = "poll-28"
            }

            textLabel.text = text
            button.configuration?.image = UIImage(imageLiteralResourceName: imageName)
            accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "format-\(attachmentType.rawValue)")
        }
    }
}
