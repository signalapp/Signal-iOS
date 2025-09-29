//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

final class UsernameLinkTooltipView: TooltipView {

    private let hInsetFromReferenceView: CGFloat
    private let onDismiss: () -> Void

    init(
        fromView: UIView,
        referenceView: UIView,
        hInsetFromReferenceView: CGFloat,
        onDismiss: @escaping () -> Void
    ) {
        self.hInsetFromReferenceView = hInsetFromReferenceView
        self.onDismiss = onDismiss

        super.init(
            fromView: fromView,
            widthReferenceView: referenceView,
            tailReferenceView: referenceView,
            wasTappedBlock: nil
        )
    }

    required init?(coder aDecoder: NSCoder) {
        owsFail("Not implemented!")
    }

    override var dismissOnTap: Bool { false }

    // MARK: - Content view

    private lazy var shareIconImageView: UIImageView = {
        let imageView = UIImageView(image: Theme.iconImage(.buttonShare))

        imageView.tintColor = Theme.primaryIconColor
        imageView.autoSetDimensions(to: .square(24))

        return imageView
    }()

    private lazy var xIconButton: UIButton = {
        let button = UIButton()

        button.setImage(Theme.iconImage(.buttonX), for: .normal)
        button.tintColor = .ows_gray45
        button.autoSetDimensions(to: .square(20))
        button.addTarget(self, action: #selector(xButtonTapped), for: .touchDown)

        return button
    }()

    private lazy var titleLabel: UILabel = {
        let label = UILabel()

        label.font = .dynamicTypeSubheadline.semibold()
        label.textColor = Theme.primaryTextColor
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.text = OWSLocalizedString(
            "USERNAME_LINK_TOOLTIP_TITLE",
            comment: "Title for a tooltip describing ways to share your username."
        )

        return label
    }()

    private lazy var subtitleLabel: UILabel = {
        let label = UILabel()

        label.font = .dynamicTypeFootnote
        label.textColor = Theme.secondaryTextAndIconColor
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.text = OWSLocalizedString(
            "USERNAME_LINK_TOOLTIP_SUBTITLE",
            comment: "Subtitle for a tooltip describing ways to share your username."
        )

        return label
    }()

    override func bubbleContentView() -> UIView {
        let hSpacing: CGFloat = 12

        let wrapper = UIView()

        wrapper.addSubview(shareIconImageView)
        wrapper.addSubview(titleLabel)
        wrapper.addSubview(subtitleLabel)
        wrapper.addSubview(xIconButton)
        wrapper.layoutMargins = UIEdgeInsets(margin: 16)

        shareIconImageView.autoPinLeadingToSuperviewMargin()
        shareIconImageView.autoPinTopToSuperviewMargin()

        xIconButton.autoPinEdge(toSuperviewEdge: .trailing, withInset: 8)
        xIconButton.autoPinEdge(toSuperviewEdge: .top, withInset: 8)

        titleLabel.autoPinTopToSuperviewMargin()
        titleLabel.autoPinEdge(.leading, to: .trailing, of: shareIconImageView, withOffset: hSpacing)
        titleLabel.autoPinEdge(.trailing, to: .leading, of: xIconButton, withOffset: -hSpacing)

        titleLabel.autoPinEdge(.bottom, to: .top, of: subtitleLabel)

        subtitleLabel.autoPinEdge(.leading, to: .trailing, of: shareIconImageView, withOffset: hSpacing)
        subtitleLabel.autoPinEdge(.trailing, to: .leading, of: xIconButton, withOffset: -hSpacing)
        subtitleLabel.autoPinBottomToSuperviewMargin()

        return wrapper
    }

    override var stretchesBubbleHorizontally: Bool {
        true
    }

    override var bubbleRounding: CGFloat {
        OWSTableViewController2.cellRounding
    }

    override var bubbleHSpacing: CGFloat {
        hInsetFromReferenceView
    }

    override var bubbleColor: UIColor {
        if UIAccessibility.isReduceTransparencyEnabled {
            return Theme.isDarkThemeEnabled ? .ows_black : .ows_white
        }

        return Theme.isDarkThemeEnabled ? .ows_blackAlpha80 : .ows_whiteAlpha80
    }

    override var bubbleBlur: Bool {
        true
    }

    override var tailDirection: TooltipView.TailDirection {
        .up
    }

    override func setupRelationshipWithSuperview(
        superview: UIView,
        tailReferenceView: UIView,
        widthReferenceView: UIView
    ) {
        self.layer.opacity = .zero
        if !UIAccessibility.isReduceMotionEnabled {
            self.transform = .scale(0)
        }

        super.setupRelationshipWithSuperview(
            superview: superview,
            tailReferenceView: tailReferenceView,
            widthReferenceView: widthReferenceView
        )

        let animator = self.transitionAnimator()
        animator.addAnimations {
            self.layer.opacity = 1
            self.transform = .identity
        }
        // Add a half-second delay for the view controller push transition.
        animator.startAnimation(afterDelay: 0.5)
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let offset = self.bounds.height / -2
        self.layer.anchorPoint.y = 0

        if verticalConstraint?.constant != offset {
            verticalConstraint?.constant = offset
        }
    }

    // MARK: Animation

    func dismissWithAnimation() {
        guard CurrentAppContext().isAppForegroundAndActive() else {
            return self.removeFromSuperview()
        }

        let animator = self.transitionAnimator()
        animator.addAnimations {
            if !UIAccessibility.isReduceMotionEnabled {
                // Views can't animate to a size of 0
                self.transform = .scale(.ulpOfOne)
            }
            self.layer.opacity = .zero
        }
        animator.addCompletion { _ in
            self.removeFromSuperview()
        }
        animator.startAnimation()
    }

    private func transitionAnimator() -> UIViewPropertyAnimator {
        UIViewPropertyAnimator(
            duration: 0.35,
            springDamping: 0.8,
            springResponse: 0.35
        )
    }

    // MARK: - Events

    @objc
    private func xButtonTapped() {
        onDismiss()
    }
}
