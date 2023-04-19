//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit

class ExpandableContactListView: UIView {

    var contactNames: [String] = [] {
        didSet {
            guard #available(iOS 13, *) else {
                textLabel.text = contactNames.joined(separator: ", ")
                return
            }
            textLabel.text = ListFormatter().string(from: contactNames)
        }
    }

    var expanded: Bool = false {
        didSet {
            scrollView.isScrollEnabled = expanded
            scrollViewMaxWidthConstraint?.isActive = !expanded
            if !expanded {
                scrollView.contentOffset = .zero
            }
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        textLabel.textColor = tintColor

        let pillView = PillView()
        pillView.layoutMargins = UIEdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 0)
        pillView.autoSetDimension(.height, toSize: RoundMediaButton.visibleButtonSize)
        addSubview(pillView)
        pillView.autoPinEdgesToSuperviewEdges()

        let backgroundView = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
        pillView.addSubview(backgroundView)
        backgroundView.autoPinEdgesToSuperviewEdges()

        let arrowView = UIImageView(image: UIImage(imageLiteralResourceName: "arrow-up-16"))
        pillView.addSubview(arrowView)
        arrowView.autoPinEdge(toSuperviewMargin: .leading, withInset: 2)
        arrowView.autoVCenterInSuperview()

        scrollViewContainer.clipsToBounds = true
        scrollViewContainer.layoutMargins = UIEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: ExpandableContactListView.gradientWidth)
        pillView.addSubview(scrollViewContainer)
        scrollViewContainer.autoPinEdges(toSuperviewMarginsExcludingEdge: .leading)
        scrollViewContainer.leadingAnchor.constraint(equalTo: arrowView.trailingAnchor, constant: 4).isActive = true

        scrollView.delegate = self
        scrollView.clipsToBounds = false
        scrollView.isScrollEnabled = expanded
        scrollViewContainer.addSubview(scrollView)
        scrollView.autoPinEdgesToSuperviewMargins()

        scrollView.addSubview(textLabel)
        textLabel.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor).isActive = true
        textLabel.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor).isActive = true
        textLabel.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor).isActive = true
        textLabel.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor).isActive = true
        scrollView.heightAnchor.constraint(equalTo: textLabel.heightAnchor).isActive = true

        // This constraint sets intrinsic content width on the scroll view.
        addConstraint({
            let constraint = scrollView.widthAnchor.constraint(equalTo: textLabel.widthAnchor)
            constraint.priority = .defaultLow
            return constraint
        }())

        // Limit scroll view width in expanded state to 128 pts.
        let scrollViewMaxWidthConstraint = scrollViewContainer.widthAnchor.constraint(lessThanOrEqualToConstant: 128)
        if !expanded {
            addConstraint(scrollViewMaxWidthConstraint)
        }
        self.scrollViewMaxWidthConstraint = scrollViewMaxWidthConstraint

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleSingleTap(gestureRecognizer:))))
    }

    @available(*, unavailable, message: "Use init(frame:)")
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        textLabel.textColor = tintColor
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        DispatchQueue.main.async {
            self.updateTextLabelEdgesFading()
        }
    }

    // MARK: - Layout

    private let scrollViewContainer = UIView()

    private let scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = false
        return scrollView
    }()

    private let textLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        label.lineBreakMode = .byClipping
        label.font = .dynamicTypeBody2Clamped
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private var scrollViewMaxWidthConstraint: NSLayoutConstraint?
    static private let gradientWidth: CGFloat = 14
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

        let gradientStopLocations: [CGFloat] = [ 0, gradientWidthInPercent, 1-gradientWidthInPercent, 1 ]
        var gradientColors: [UIColor] = [ .black, .black ]
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
}

extension ExpandableContactListView {

    @objc
    private func handleSingleTap(gestureRecognizer: UITapGestureRecognizer) {
        expanded = !expanded
        UIView.animate(withDuration: 0.3,
                       animations: {
            self.superview?.setNeedsLayout()
            self.superview?.layoutIfNeeded()
            if self.expanded {
                self.updateTextLabelEdgesFading()
            }
        },
                       completion: { _ in
            self.updateTextLabelEdgesFading()
        })
    }
}

extension ExpandableContactListView: UIScrollViewDelegate {

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateTextLabelEdgesFading()
    }
}
