//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import UIKit

class AttachmentApprovalTopBar: MediaTopBar {

    // MARK: - Subviews

    lazy var cancelButton: UIButton = {
        let button = UIButton(configuration: .roundMedia(
            image: UIImage(imageLiteralResourceName: "x"),
            size: 44,
        ))
        button.accessibilityLabel = CommonStrings.dismissButton
        return button
    }()

    lazy var backButton: UIButton = {
        let backButton = UIButton(configuration: .roundMedia(
            image: UIImage(imageLiteralResourceName: "chevron-left-26"),
            size: 44,
        ))
        backButton.accessibilityLabel = CommonStrings.backButton
        return backButton
    }()

    private lazy var recipientListView = ExpandableContactListView()

    // MARK: - Updates

    func update(withRecipientNames recipientNames: [String]) {
        guard !recipientNames.isEmpty else {
            recipientListView.isHiddenInStackView = true
            return
        }

        recipientListView.isHiddenInStackView = false
        recipientListView.contactNames = recipientNames
    }

    // MARK: - UIView

    init(options: AttachmentApprovalViewControllerOptions) {
        super.init(frame: .zero)

        let leadingButton: UIButton
        if options.contains(.hasCancel) {
            leadingButton = cancelButton
        } else {
            leadingButton = backButton
        }
        let spacerView = UIView.hStretchingSpacer()
        let stackView = UIStackView(arrangedSubviews: [leadingButton, spacerView, recipientListView])
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.alignment = .center
        addSubview(stackView)
        addConstraints([
            leadingButton.leadingAnchor.constraint(equalTo: controlsLayoutGuide.leadingAnchor),
            stackView.topAnchor.constraint(equalTo: controlsLayoutGuide.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: controlsLayoutGuide.bottomAnchor),
            stackView.trailingAnchor.constraint(equalTo: controlsLayoutGuide.trailingAnchor),
            spacerView.widthAnchor.constraint(greaterThanOrEqualToConstant: 24),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - ExpandableContactListView

    private class ExpandableContactListView: UIView, UIScrollViewDelegate {

        private class var listFormatter: ListFormatter {
            let formatter = ListFormatter()
            if let identifier = NSLocale.preferredLanguages.first {
                formatter.locale = Locale(identifier: identifier)
            }
            return formatter
        }

        var contactNames: [String] = [] {
            didSet {
                textLabel.text = Self.listFormatter.string(from: contactNames)
            }
        }

        var expanded: Bool = false {
            didSet {
                scrollView.isScrollEnabled = expanded
                scrollViewMaxWidthConstraint.isActive = !expanded
                if !expanded {
                    scrollView.contentOffset = .zero
                }
            }
        }

        override init(frame: CGRect) {
            super.init(frame: frame)

            let visualEffectView: UIVisualEffectView
            if #available(iOS 26, *) {
                let glassEffect = UIGlassEffect(style: .regular)
                glassEffect.isInteractive = true

                visualEffectView = UIVisualEffectView(effect: glassEffect)
                visualEffectView.cornerConfiguration = .capsule()
                visualEffectView.clipsToBounds = true
                visualEffectView.translatesAutoresizingMaskIntoConstraints = false
                addSubview(visualEffectView)

                NSLayoutConstraint.activate([
                    visualEffectView.topAnchor.constraint(equalTo: topAnchor),
                    visualEffectView.leadingAnchor.constraint(equalTo: leadingAnchor),
                    visualEffectView.trailingAnchor.constraint(equalTo: trailingAnchor),
                    visualEffectView.bottomAnchor.constraint(equalTo: bottomAnchor),
                ])
            } else {
                let pillView = PillView()
                pillView.translatesAutoresizingMaskIntoConstraints = false
                addSubview(pillView)

                visualEffectView = UIVisualEffectView(effect: UIBlurEffect(style: .regular))
                visualEffectView.translatesAutoresizingMaskIntoConstraints = false
                pillView.addSubview(visualEffectView)

                NSLayoutConstraint.activate([
                    pillView.topAnchor.constraint(equalTo: topAnchor),
                    pillView.leadingAnchor.constraint(equalTo: leadingAnchor),
                    pillView.trailingAnchor.constraint(equalTo: trailingAnchor),
                    pillView.bottomAnchor.constraint(equalTo: bottomAnchor),

                    visualEffectView.topAnchor.constraint(equalTo: pillView.topAnchor),
                    visualEffectView.leadingAnchor.constraint(equalTo: pillView.leadingAnchor),
                    visualEffectView.trailingAnchor.constraint(equalTo: pillView.trailingAnchor),
                    visualEffectView.bottomAnchor.constraint(equalTo: pillView.bottomAnchor),
                ])
            }

            let arrowUp = UIImageView(image: UIImage(imageLiteralResourceName: "arrow-up-compact"))
            arrowUp.tintColor = .Signal.label
            arrowUp.translatesAutoresizingMaskIntoConstraints = false
            visualEffectView.contentView.addSubview(arrowUp)

            scrollViewContainer.translatesAutoresizingMaskIntoConstraints = false
            visualEffectView.contentView.addSubview(scrollViewContainer)

            scrollView.translatesAutoresizingMaskIntoConstraints = false
            scrollViewContainer.addSubview(scrollView)

            textLabel.translatesAutoresizingMaskIntoConstraints = false
            scrollView.addSubview(textLabel)

            NSLayoutConstraint.activate([
                arrowUp.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor, constant: 10),
                arrowUp.centerYAnchor.constraint(equalTo: visualEffectView.centerYAnchor),

                scrollViewContainer.topAnchor.constraint(equalTo: visualEffectView.topAnchor),
                scrollViewContainer.leadingAnchor.constraint(equalTo: arrowUp.trailingAnchor, constant: 4),
                scrollViewContainer.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor),
                scrollViewContainer.bottomAnchor.constraint(equalTo: visualEffectView.bottomAnchor),

                scrollView.frameLayoutGuide.topAnchor.constraint(
                    equalTo: scrollViewContainer.topAnchor,
                ),
                scrollView.frameLayoutGuide.leadingAnchor.constraint(
                    equalTo: scrollViewContainer.leadingAnchor,
                ),
                scrollView.frameLayoutGuide.trailingAnchor.constraint(
                    equalTo: scrollViewContainer.trailingAnchor,
                    constant: -Self.gradientWidth,
                ),
                scrollView.frameLayoutGuide.bottomAnchor.constraint(
                    equalTo: scrollViewContainer.bottomAnchor,
                ),

                textLabel.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
                textLabel.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
                textLabel.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
                textLabel.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
                scrollView.frameLayoutGuide.heightAnchor.constraint(equalTo: textLabel.heightAnchor),
                {
                    // This constraint sets intrinsic content width on the scroll view.
                    let constraint = scrollView.widthAnchor.constraint(equalTo: textLabel.widthAnchor)
                    constraint.priority = .defaultLow
                    return constraint
                }(),
            ])

            // Limit scroll view width in expanded state to 128 pts.
            scrollViewMaxWidthConstraint = scrollViewContainer.widthAnchor.constraint(
                lessThanOrEqualToConstant: 128,
            )
            if expanded == false {
                scrollViewMaxWidthConstraint.isActive = true
            }

            addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleSingleTap(gestureRecognizer:))))
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            DispatchQueue.main.async {
                self.updateTextLabelEdgesFading()
            }
        }

        override var intrinsicContentSize: CGSize {
            CGSize(width: UIView.noIntrinsicMetric, height: 44)
        }

        // MARK: - Layout

        private let scrollViewContainer: UIView = {
            let view = UIView()
            view.clipsToBounds = true
            return view
        }()

        private lazy var scrollView: UIScrollView = {
            let scrollView = UIScrollView()
            scrollView.delegate = self
            scrollView.clipsToBounds = false
            scrollView.isScrollEnabled = expanded
            scrollView.showsVerticalScrollIndicator = false
            scrollView.showsHorizontalScrollIndicator = false
            scrollView.alwaysBounceHorizontal = false
            return scrollView
        }()

        private let textLabel: UILabel = {
            let label = UILabel()
            label.numberOfLines = 1
            label.lineBreakMode = .byClipping
            label.font = .dynamicTypeSubheadlineClamped
            label.textColor = .Signal.label
            label.translatesAutoresizingMaskIntoConstraints = false
            return label
        }()

        private var scrollViewMaxWidthConstraint: NSLayoutConstraint!
        private static let gradientWidth: CGFloat = 14
        private var isLeadingEdgeFaded = false
        private var isTrailingEdgeFaded = false

        private func updateTextLabelEdgesFading() {
            // This method would be called in a tight loop when users scrolls.
            // Therefore only re-create mask layer if it is necessary.
            let shouldFadeLeading = scrollView.contentOffset.x > 0
            let shouldFadeTrailing = scrollView.contentOffset.x < scrollView.contentSize.width - scrollView.frame.width
            var shouldUpdateLayerMask = shouldFadeLeading != isLeadingEdgeFaded || shouldFadeTrailing != isTrailingEdgeFaded

            // Mask layer doesn't resize automatically and therefore width change
            // (switching to/from expanded state) mandates mask update.
            if !shouldUpdateLayerMask, let maskLayer = scrollViewContainer.layer.mask {
                shouldUpdateLayerMask = maskLayer.bounds.width != scrollViewContainer.width
            }

            guard shouldUpdateLayerMask else {
                return
            }

            isLeadingEdgeFaded = shouldFadeLeading
            isTrailingEdgeFaded = shouldFadeTrailing

            // Simplest case: no edge fading - no mask layer.
            guard isLeadingEdgeFaded || isTrailingEdgeFaded else {
                scrollViewContainer.layer.mask = nil
                return
            }

            let gradientWidthInPercent = Self.gradientWidth / scrollViewContainer.width

            let gradientStopLocations: [CGFloat] = [0, gradientWidthInPercent, 1 - gradientWidthInPercent, 1]
            var gradientColors: [UIColor] = [.black, .black]
            gradientColors.insert(isLeadingEdgeFaded ? .clear : .black, at: 0)
            gradientColors.append(isTrailingEdgeFaded ? .clear : .black)

            let gradientLayer = CAGradientLayer()
            gradientLayer.frame = scrollViewContainer.bounds
            gradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
            gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
            gradientLayer.colors = gradientColors.map { $0.cgColor }
            gradientLayer.locations = gradientStopLocations.map { NSNumber(value: $0) }
            scrollViewContainer.layer.mask = gradientLayer
        }

        @objc
        private func handleSingleTap(gestureRecognizer: UITapGestureRecognizer) {
            expanded = !expanded
            UIView.animate(
                withDuration: 0.3,
                animations: {
                    self.superview?.setNeedsLayout()
                    self.superview?.layoutIfNeeded()
                    if self.expanded {
                        self.updateTextLabelEdgesFading()
                    }
                },
                completion: { _ in
                    self.updateTextLabelEdgesFading()
                },
            )
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            updateTextLabelEdgesFading()
        }
    }
}
