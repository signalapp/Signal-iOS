//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import UIKit

public class SelectionIndicatorView: UIView {

    public enum Style {
        /// Use in lists over plain colored background.
        case list
        /// Use over media.
        case media
    }

    // MARK: UIView

    public init(style: Style = .list) {
        self.style = style

        super.init(frame: .init(origin: .zero, size: .square(SelectionIndicatorView.preferredSize)))

        // Because it is often paired with UILabels, we want to make
        // this view as compact and as compression resistant as possible.
        setContentHuggingPriority(.defaultHigh, for: .horizontal)
        setContentHuggingPriority(.defaultHigh, for: .vertical)
        setContentCompressionResistancePriority(.required - 10, for: .horizontal)
        setContentCompressionResistancePriority(.required - 10, for: .vertical)

        switch style {
        case .list:
            addSubview(innerRing)
        case .media:
            addSubview(outerRing)
        }
        addSubview(selectedView)
        updateAppearance(animated: false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Layout

    private static let preferredSize: CGFloat = 24

    private static let ringStrokeWidth: CGFloat = 2

    private static let innerRingInset: CGFloat = 1

    override public var intrinsicContentSize: CGSize {
        .square(Self.preferredSize)
    }

    override public func layoutSubviews() {
        super.layoutSubviews()

        switch style {
        case .list:
            innerRing.center = bounds.center
            // Inner ring is inset by 1dp relative to the view's bounds.
            // Filled circle (checkmark's background) has the same diameter as inner ring.
            let circleDiameter = Self.preferredSize - 2 * Self.innerRingInset
            innerRing.bounds.size = .square(circleDiameter)
            selectedView.bounds.size = .square(circleDiameter)
        case .media:
            outerRing.center = bounds.center
            outerRing.bounds.size = .square(Self.preferredSize)
            // Filled circle (checkmark's background) fills inside of the outer ring.
            selectedView.bounds.size = .square(Self.preferredSize - 2 * Self.ringStrokeWidth)
        }

        selectedView.center = bounds.center

        // Checkmark is self-sized and only needs to be centered properly.
        checkmarkIcon.center = selectedView.bounds.center
    }

    // MARK: State

    private var _isSelected: Bool = false

    public var isSelected: Bool {
        get { _isSelected }
        set { setIsSelected(newValue, animated: false) }
    }

    public func setIsSelected(_ isSelected: Bool, animated: Bool) {
        guard isSelected != _isSelected else { return }
        _isSelected = isSelected
        updateAppearance(animated: animated)
    }

    private var _isEnabled: Bool = true

    public var isEnabled: Bool {
        get { _isEnabled }
        set { setIsEnabled(newValue, animated: false) }
    }

    public func setIsEnabled(_ isEnabled: Bool, animated: Bool) {
        guard isEnabled != _isEnabled else { return }
        _isEnabled = isEnabled
        updateAppearance(animated: animated)
    }

    // Make this a `let` to simplify layout and avoid overhead of creating unused views.
    // The assumption is to only reference `innerRing` when style is `list`
    // and only reference `outerRing` when style is `media`.
    public let style: Style

    // MARK: Appearance

    /// Color that fills the selection ring and is the background for checkmark image.
    public var fillColor: UIColor = .Signal.accent {
        didSet {
            selectedView.backgroundColor = fillColor
        }
    }

    private var effectiveFillColor: UIColor {
        isEnabled ? fillColor : .Signal.tertiaryLabel
    }

    /// Color for the ckeckmark image and outer ring for media-style indicators.
    public var strokeColor: UIColor = .white {
        didSet {
            checkmarkIcon.tintColor = strokeColor
            if case .media = style {
                outerRing.tintColor = strokeColor
            }
        }
    }

    private lazy var innerRing: UIView = {
        owsAssertDebug(style == .list, "Invalid access")
        let ringView = RingView()
        ringView.lineWidth = SelectionIndicatorView.ringStrokeWidth
        ringView.tintColor = .Signal.tertiaryLabel
        return ringView
    }()

    private lazy var outerRing: UIView = {
        owsAssertDebug(style == .media, "Invalid access")
        let ringView = RingView()
        ringView.lineWidth = SelectionIndicatorView.ringStrokeWidth
        ringView.tintColor = strokeColor
        return ringView
    }()

    private lazy var selectedView: UIView = {
        let circleView = CircleView()
        circleView.backgroundColor = effectiveFillColor
        circleView.addSubview(checkmarkIcon)
        return circleView
    }()

    private lazy var checkmarkIcon: UIImageView = {
        let imageView = UIImageView(image: UIImage(named: "check-compact"))
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = strokeColor
        return imageView
    }()

    private func updateAppearance(animated: Bool) {
        if case .list = style {
            innerRing.setIsHidden(isSelected, animated: animated)
        }
        // Outer ring is always visible.
        selectedView.setIsHidden(isSelected == false, animated: animated)

        selectedView.backgroundColor = effectiveFillColor
    }
}
