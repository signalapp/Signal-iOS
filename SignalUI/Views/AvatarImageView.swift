//
// Copyright 2016 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit

@objc
open class AvatarImageView: UIImageView, CVView {

    @objc
    public var shouldDeactivateConstraints = false

    public init() {
        super.init(frame: .zero)
        self.configureView()
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.configureView()
    }

    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        self.configureView()
    }

    public override init(image: UIImage?) {
        super.init(image: image)
        self.configureView()
    }

    public init(shouldDeactivateConstraints: Bool) {
        self.shouldDeactivateConstraints = shouldDeactivateConstraints
        super.init(frame: .zero)
        self.configureView()
    }

    func configureView() {
        self.autoPinToSquareAspectRatio()

        self.layer.minificationFilter = .trilinear
        self.layer.magnificationFilter = .trilinear
        self.layer.masksToBounds = true

        self.contentMode = .scaleToFill
    }

    override public func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = frame.size.width / 2
    }

    public override func updateConstraints() {
        super.updateConstraints()

        if shouldDeactivateConstraints {
            deactivateAllConstraints()
        }
    }

    public func reset() {
        self.image = nil
    }
}

// MARK: -

@objc
public class AvatarImageButton: UIButton {

    // MARK: - Button Overrides

    override public func layoutSubviews() {
        super.layoutSubviews()

        layer.cornerRadius = frame.size.width / 2
    }

    override public func setImage(_ image: UIImage?, for state: UIControl.State) {
        ensureViewConfigured()
        super.setImage(image, for: state)
    }

    // MARK: Private

    var hasBeenConfigured = false
    func ensureViewConfigured() {
        guard !hasBeenConfigured else {
            return
        }
        hasBeenConfigured = true

        autoPinToSquareAspectRatio()

        layer.minificationFilter = .trilinear
        layer.magnificationFilter = .trilinear
        layer.masksToBounds = true

        contentMode = .scaleToFill
    }
}
