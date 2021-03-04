//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import UIKit

@objc
public class OWSButton: UIButton {

    @objc
    public var block: () -> Void = { }

    public var downStateView: UIView? {
        didSet {
            oldValue?.removeFromSuperview()

            if let downStateView = downStateView {
                addSubview(downStateView)

                ensureDownGestureRecognizer()
            }

            applyDownState()
        }
    }

    private var isDown: Bool = false {
        didSet {
            applyDownState()
        }
    }

    // MARK: -

    @objc
    public init(block: @escaping () -> Void = { }) {
        super.init(frame: .zero)

        self.block = block
        ensureTapGestureRecognizer()
    }

    @objc
    public init(title: String, block: @escaping () -> Void = { }) {
        super.init(frame: .zero)

        self.block = block
        ensureTapGestureRecognizer()
        setTitle(title, for: .normal)
    }

    @objc
    public init(imageName: String,
         tintColor: UIColor?,
         block: @escaping () -> Void = { }) {
        super.init(frame: .zero)

        self.block = block
        ensureTapGestureRecognizer()

        setImage(imageName: imageName)
        self.tintColor = tintColor
    }

    @objc
    public func setImage(imageName: String?) {
        guard let imageName = imageName else {
            setImage(nil, for: .normal)
            return
        }
        if let image = UIImage(named: imageName) {
            setImage(image.withRenderingMode(.alwaysTemplate), for: .normal)
        } else {
            owsFailDebug("Missing asset: \(imageName)")
        }
    }

    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func applyDownState() {
        guard let downStateView = downStateView else {
            return
        }
        downStateView.isHidden = !isDown
    }

    private var downGestureRecognizer: DownStateGestureRecognizer?

    private func ensureDownGestureRecognizer() {
        if downGestureRecognizer != nil {
            return
        }
        let downGestureRecognizer = DownStateGestureRecognizer { [weak self] in
            guard let self = self,
                  let downGestureRecognizer = self.downGestureRecognizer else {
                return
            }
            self.isDown = downGestureRecognizer.hasValidTouch
        }
        addGestureRecognizer(downGestureRecognizer)
        self.downGestureRecognizer = downGestureRecognizer
    }

    private var tapGestureRecognizer: UIGestureRecognizer?

    private func ensureTapGestureRecognizer() {
        if tapGestureRecognizer != nil {
            return
        }
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(didTap))
        addGestureRecognizer(tapGestureRecognizer)
        self.tapGestureRecognizer = tapGestureRecognizer
    }

    // MARK: - Common Style Reuse

    @objc
    public class func sendButton(imageName: String, block: @escaping () -> Void) -> OWSButton {
        let button = OWSButton(imageName: imageName, tintColor: .white, block: block)

        let buttonWidth: CGFloat = 40
        button.layer.cornerRadius = buttonWidth / 2
        button.autoSetDimensions(to: CGSize(square: buttonWidth))

        button.backgroundColor = .ows_accentBlue

        return button
    }

    /// Mimics a UIBarButtonItem of type .cancel, but with a shadow.
    @objc
    public class func shadowedCancelButton(block: @escaping () -> Void) -> OWSButton {
        let cancelButton = OWSButton(title: CommonStrings.cancelButton, block: block)
        cancelButton.setTitleColor(.white, for: .normal)
        if let titleLabel = cancelButton.titleLabel {
            titleLabel.font = UIFont.systemFont(ofSize: 18.0)
            titleLabel.layer.shadowColor = UIColor.black.cgColor
            titleLabel.setShadow()
        } else {
            owsFailDebug("Missing titleLabel.")
        }
        cancelButton.sizeToFit()
        return cancelButton
    }

    @objc
    public class func navigationBarButton(imageName: String, block: @escaping () -> Void) -> OWSButton {
        let button = OWSButton(imageName: imageName, tintColor: .white, block: block)
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowRadius = 2
        button.layer.shadowOpacity = 0.66
        button.layer.shadowOffset = .zero
        return button
    }

    // MARK: -

    @objc
    func didTap() {
        block()
    }
}

// MARK: -

// A GR used by OWSButton to detect "down state".
//
// This GR is unusual; it must not interfere with its views other GRs.
// It can't "recognize" without blocking other GRs from recognizing.
// Therefore it never changes its own state.  It uses a callback block
// to notify its view of changes to down state.
//
// A button must be tapped.  This GR is a bit more permissive than that.
// It will remain down for a long press even though that isn't a valid tap.
// Although it is not "down" if a long press leaves the views bounds, it
// will re-enter "down" if the long press re-enters the views bounds.
// This gives a sense of physicality to the the button.
public class DownStateGestureRecognizer: UIGestureRecognizer {

    public typealias Callback = () -> Void
    private final let callback: Callback

    public required init(callback: @escaping Callback) {
        self.callback = callback

        super.init(target: nil, action: nil)
    }

    public var hasValidTouch = false {
        didSet {
            if hasValidTouch != oldValue {
                callback()
            }
        }
    }

    @objc
    public override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool {
        return false
    }

    @objc
    public override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool {
        return false
    }

    @objc
    public override func shouldRequireFailure(of otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return false
    }

    @objc
    public override func shouldBeRequiredToFail(by otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return false
    }

    @objc
    public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        handle(event: event)
    }

    @objc
    public override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        handle(event: event)
    }

    @objc
    public override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        handle(event: event)
    }

    @objc
    public override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        handle(event: event)
    }

    private func handle(event: UIEvent) {
        // Consider the button down if there is a a single active
        // touch within the views bounds.
        self.hasValidTouch = { () -> Bool in
            guard let allTouches = event.allTouches,
                  allTouches.count == 1,
                  let touch = allTouches.first else {
                return false
            }
            guard let view = self.view else {
                return false
            }
            let location = touch.location(in: view)
            guard view.bounds.contains(location) else {
                return false
            }

            switch touch.phase {
            case .began, .moved, .stationary:
                break
            case .ended, .cancelled:
                return false
            case .regionEntered, .regionMoved, .regionExited:
                return false
            @unknown default:
                return false
            }

            return true
        }()
    }
}
