//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalMessaging
import UIKit

class RotationControl: UIControl {

    private var previousAngle: CGFloat = 0
    private var _angle: CGFloat = 0
    /**
     * Measured in degrees.
     */
    var angle: CGFloat {
        get {
            _angle
        }
        set {
            setAngle(newValue, updateScrollViewOffset: true)
        }
    }

    /**
     * Rotation angle as user sees it, ie not taking into account 90 degree rotations that might have been made.
     */
    private var normalizedAngle: CGFloat {
        return angle - canvasRotation
    }

    /**
     * Scroll view's content offset does not need to be updated if user is scrolling.
     */
    private func setAngle(_ angle: CGFloat, updateScrollViewOffset: Bool = true) {
        previousAngle = _angle
        _angle = angle
        canvasRotation = angle - angle.remainder(dividingBy: 90)
        updateAppearance()
        if updateScrollViewOffset {
            updateScrollViewContentOffset()
        }
        // Haptic feedback.
        if isTracking {
            let roundingRule: FloatingPointRoundingRule
            if abs(angle) > abs(previousAngle) {
                // Moving away from zero.
                roundingRule = .towardZero
            } else {
                // Moving towards zero
                roundingRule = .awayFromZero
            }

            let angleRounded = angle.rounded(roundingRule)
            let previousAngleRounded = previousAngle.rounded(roundingRule)
            if previousAngleRounded != angleRounded && angleRounded.truncatingRemainder(dividingBy: Constants.stepValue) == 0 {
                hapticFeedbackGenerator.selectionChanged()
            }
        }
    }

    /**
     * Measured in degrees.
     */
    private var canvasRotation: CGFloat = 0

    required init() {
        super.init(frame: .zero)

        layoutMargins = .zero
        tintColor = .ows_white

        // Text Label
        textLabel.setCompressionResistanceVerticalHigh()
        textLabel.setContentHuggingVerticalHigh()
        addSubview(textLabel)
        textLabel.autoPinTopToSuperviewMargin()
        textLabel.autoHCenterInSuperview()
        textLabel.isUserInteractionEnabled = true
        textLabel.addGestureRecognizer({
            let gestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
            gestureRecognizer.numberOfTapsRequired = 2
            return gestureRecognizer
        }())

        // Band
        addSubview(scrollView)
        scrollView.autoSetDimension(.height, toSize: Constants.bandHeight)
        scrollView.autoPinWidthToSuperviewMargins()
        scrollView.autoPinEdge(.top, to: .bottom, of: textLabel, withOffset: 8)
        scrollView.autoPinBottomToSuperviewMargin()
        initializeRuler()

        // Current Value Marking
        currentValueMark.backgroundColor = UIColor.color(rgbHex: 0x62E87A)
        addSubview(currentValueMark)
        currentValueMark.autoSetDimension(.width, toSize: Constants.markingWidth)
        currentValueMark.autoPinEdge(.top, to: .top, of: scrollView)
        currentValueMark.autoPinEdge(.bottom, to: .bottom, of: scrollView)
        currentValueMark.autoHCenterInSuperview()

        updateFont()
        updateColors()
        updateAppearance()
    }

    @available(*, unavailable, message: "Use init()")
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if !scrollView.isDragging {
            updateScrollViewLayout()
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.preferredContentSizeCategory != previousTraitCollection?.preferredContentSizeCategory {
            updateFont()
        }
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        updateColors()
    }

    override var isTracking: Bool {
        scrollView.isTracking
    }

    private static let preferredWidth: CGFloat = {
        if UIDevice.current.isIPad {
            return 428 // screen width on iPhone 13 max
        } else {
            return min(UIScreen.main.bounds.width, UIScreen.main.bounds.height)
        }
    }()

    override var intrinsicContentSize: CGSize {
        // Define preferred width for when width is not constrained externally (iPad).
        CGSize(width: RotationControl.preferredWidth, height: UIView.noIntrinsicMetric)
    }

    private lazy var hapticFeedbackGenerator = SelectionHapticFeedback()

    // MARK: - Layout

    private let numberFormatter: NumberFormatter = {
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .decimal
        return numberFormatter
    }()

    private let textLabel = UILabel()
    private let scrollView = UIScrollView()
    private let rulerView = UIView()
    private let currentValueMark = UIView()

    private struct Constants {
        static let stepRange = -45...45         // 45 degrees each direction
        static let stepValue: CGFloat = 3       // 1 mark = 3 degrees
        static let stepWidth: CGFloat = 12      // distance between markings
        static let markingWidth: CGFloat = 2*CGHairlineWidth()
        static let bandHeight: CGFloat = 32
        static let markingHeight: CGFloat = 12
    }

    private func updateFont() {
        textLabel.font = .ows_dynamicTypeBody2Clamped.ows_monospaced
    }

    private func updateColors() {
        textLabel.textColor = tintColor
    }

    private func updateAppearance() {
        var roundedAngle = normalizedAngle.rounded()
        if roundedAngle == 0 && roundedAngle.sign == .minus {
            roundedAngle = 0
        }
        textLabel.text = numberFormatter.string(for: roundedAngle)
        currentValueMark.isHidden = abs(angle) < .epsilon
    }

    @objc
    private func handleDoubleTap(_ gestureRecognizer: UITapGestureRecognizer) {
        UIView.animate(withDuration: 0.2) {
            self.setAngle(self.canvasRotation, updateScrollViewOffset: true)
            self.sendActions(for: .valueChanged)
        }
    }
}

// MARK: - Scroll View

extension RotationControl: UIScrollViewDelegate {

    private func initializeRuler() {
        scrollView.delegate = self
        scrollView.bounces = false
        scrollView.showsHorizontalScrollIndicator = false

        let numberOfSteps = (Constants.stepRange.upperBound - Constants.stepRange.lowerBound) / Int(Constants.stepValue)
        let rulerWidth = CGFloat(numberOfSteps) * (Constants.stepWidth + Constants.markingWidth)
        rulerView.bounds.size = CGSize(width: rulerWidth, height: Constants.bandHeight)
        let markingSize = CGSize(width: Constants.markingWidth, height: Constants.markingHeight)
        let markingOriginY = rulerView.bounds.height - markingSize.height
        for i in 0...numberOfSteps {
            let marking = UIView(frame: CGRect(origin: .zero, size: markingSize))
            marking.backgroundColor = .ows_white
            marking.alpha = i%5 == 0 ? 1 : 0.5
            rulerView.addSubview(marking)
            marking.frame.origin = CGPoint(x: CGFloat(i) * (Constants.stepWidth + Constants.markingWidth) - 0.5*Constants.markingWidth,
                                           y: markingOriginY)
            if i == numberOfSteps / 2 {
                marking.frame.origin.y = 0
                marking.frame.size.height = Constants.bandHeight
            }
        }
        scrollView.addSubview(rulerView)
        updateScrollViewLayout()
    }

    private func updateScrollViewLayout() {
        scrollView.contentSize = CGSize(width: rulerView.bounds.width + scrollView.frame.width,
                                        height: rulerView.height)
        rulerView.frame.origin = CGPoint(x: 0.5 * scrollView.frame.width, y: 0)
        updateScrollViewContentOffset()
    }

    private func updateScrollViewContentOffset(animated: Bool = false) {
        scrollView.setContentOffset(scrollViewOffset(for: normalizedAngle), animated: animated)
    }

    private func scrollViewOffset(for normalizedAngle: CGFloat) -> CGPoint {
        let zeroBasedAngle = normalizedAngle - CGFloat(Constants.stepRange.lowerBound)
        let horizontalOffset = zeroBasedAngle / Constants.stepValue * (Constants.stepWidth + Constants.markingWidth)
        return CGPoint(x: horizontalOffset, y: 0)
    }

    private func currentRulerAngle() -> CGFloat {
        let horizontalOffset = scrollView.contentOffset.x
        let zeroBasedAngle = Constants.stepValue * horizontalOffset / (Constants.stepWidth + Constants.markingWidth)
        return zeroBasedAngle + CGFloat(Constants.stepRange.lowerBound)
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        sendActions(for: .editingDidBegin)
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        sendActions(for: .editingDidEnd)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView.isTracking else { return }
        let angle = currentRulerAngle() + canvasRotation
        setAngle(angle, updateScrollViewOffset: false)
        sendActions(for: .valueChanged)
    }

    func scrollViewWillBeginDecelerating(_ scrollView: UIScrollView) {
        // Kill inertia scrolling.
        updateScrollViewContentOffset(animated: true)
    }
}
