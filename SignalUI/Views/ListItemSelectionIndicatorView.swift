//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import UIKit

public class ListItemSelectionIndicatorView: UIView {

    // MARK: UIView

    override init(frame: CGRect = .init(origin: .zero, size: .square(ListItemSelectionIndicatorView.preferredSize))) {
        super.init(frame: frame)

        directionalLayoutMargins = .init(margin: 1)

        // Because it is often paired with UILabels, we want to make
        // this view as compact and as compression resistant as possible.
        setContentHuggingPriority(.defaultHigh, for: .horizontal)
        setContentHuggingPriority(.defaultHigh, for: .vertical)
        setContentCompressionResistancePriority(.required - 10, for: .horizontal)
        setContentCompressionResistancePriority(.required - 10, for: .vertical)

        sizeToFit()

        addSubview(unselectedView)
        addSubview(selectedView)
        updateAppearance(animated: false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Layout

    private static let preferredSize: CGFloat = 22

    override public var intrinsicContentSize: CGSize {
        .square(Self.preferredSize) + directionalLayoutMargins.asSize
    }

    override public func layoutSubviews() {
        super.layoutSubviews()

        let circleRadius = Self.preferredSize / 2
        let origin = CGPoint(x: bounds.center.x - circleRadius, y: bounds.center.y - circleRadius)
        let size = CGSize.square(Self.preferredSize)
        let frame = CGRect(origin: origin, size: size)
        unselectedView.frame = frame
        selectedView.frame = frame
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

    // MARK: Appearance

    private let unselectedView: UIView = {
        let ringView = RingView()
        ringView.lineWidth = 2
        ringView.tintColor = .Signal.tertiaryLabel
        return ringView
    }()

    private lazy var selectedView: UIView = {
        let circleView = CircleView()
        circleView.backgroundColor = .Signal.accent
        circleView.addSubview(checkmarkIcon)
        return circleView
    }()

    private let checkmarkIcon: UIImageView = {
        let imageView = UIImageView(image: UIImage(named: "check-compact"))
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = .white
        return imageView
    }()

    private func updateAppearance(animated: Bool) {
        selectedView.setIsHidden(isSelected == false, animated: animated)
        unselectedView.setIsHidden(isSelected, animated: animated)

        selectedView.backgroundColor = isEnabled ? .Signal.accent : .Signal.tertiaryLabel
    }
}
