//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import UIKit

/// A view capable of presenting avatar images in a standardized fashion
/// Callers can specify one of four avatar size classes. This view should not be sized to an unsupported size class
/// Badge art can be optionally provided to be overlayed on top of the avatar image. This art may bleed outside of the view bounds
/// this behavior ensures that callers can center this view to center the underlying avatar image.
///
/// This is a subclass of UIControl and can act as a button by setting a target-action.
@objc
public class AvatarImageView2: UIControl, CVView {

    /// Supported sizes of AvatarImageView
    @objc(AvatarImageViewSizeClass)
    public enum SizeClass: Int, CaseIterable {
        case tiny = 28      // 28x28
        case small = 36     // 36x36
        case medium = 56    // 56x56
        case large = 80     // 80x80
        case xlarge = 88    // 88x88

        /// The size of the avatar image and the target size of the AvatarImageView
        public var size: CGSize { CGSize(square: CGFloat(rawValue)) }

        /// The badge offset from its frame origin. Design has specified these points so the badge sits right alongside the circular avatar edge
        var badgeOffset: CGPoint {
            switch self {
            case .tiny: return CGPoint(x: 14, y: 16)
            case .small: return CGPoint(x: 20, y: 23)
            case .medium: return CGPoint(x: 32, y: 38)
            case .large: return CGPoint(x: 44, y: 52)
            case .xlarge: return CGPoint(x: 49, y: 56)
            }
        }

        /// The badge size
        var badgeSize: CGSize {
            switch self {
            case .tiny, .small: return CGSize(square: 16)
            case .medium: return CGSize(square: 24)
            case .large, .xlarge: return CGSize(square: 36)
            }
        }
    }

    @objc
    public enum Shape: Int {
        case rectangular
        case circular
    }

    // MARK: - External API

    @objc
    public var avatarImage: UIImage? {
        get { avatarView.image }
        set { avatarView.image = newValue }
    }

    @objc
    public var badgeImage: UIImage? {
        get { badgeView.image }
        set {
            owsAssertDebug(badgeProvider == nil, "Setting a badgeProvider conflicts with setting an explicit badge image")
            guard badgeImage !== badgeView.image else { return }
            badgeView.image = newValue
            setNeedsLayout()
        }
    }

    @objc
    public var badgeProvider: BadgeProvider? {
        didSet {
            guard badgeProvider !== badgeProvider else { return }
            setNeedsLayout()
        }
    }

    /// Sets the size of the AvatarImageView
    /// Callers are responsible for ensuring that the superview maintains the sizeClass size. Optionally, callers an toggle
    /// `pinBoundsToSizeClass` to automatically add autolayout constraints to maintain the view's size.
    ///
    /// Why have predefined size classes? Avatar design specs have very precise layout requirements that aren't easily generalized to arbitrary sizes
    /// See the badge placement logic in `layoutSubviews()` for more info
    @objc
    public var sizeClass: SizeClass = .medium {
        didSet {
            if pinBoundsToSizeClass {
                setNeedsUpdateConstraints()
            }
            setNeedsLayout()
        }
    }

    /// Specifies whether or not the avatar image should be masked to a circle
    @objc
    public var shape: Shape = .circular {
        didSet { setNeedsLayout() }
    }

    /// If set `true`, autolayout constraints will be added to ensure the view is sized properly.
    @objc
    public var pinBoundsToSizeClass: Bool = false {
        didSet { setNeedsUpdateConstraints() }
    }

    // MARK: - CVView

    public func reset() {
        badgeProvider = nil
        badgeImage = nil
        avatarImage = nil
    }

    // MARK: - Lifecycle

    @objc
    public init(sizeClass: SizeClass) {
        self.sizeClass = sizeClass
        super.init(frame: .zero)

        addSubview(avatarView)
        addSubview(badgeView)

        // We don't autoresize since we're anticipating to be sized at one of the predefined size classes
        // Manual layout is fully supported here anyway
        autoresizesSubviews = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var sizeConstraints: (width: NSLayoutConstraint, height: NSLayoutConstraint)? = nil
    override public func updateConstraints() {
        // Usually a no-op, but if any key properties change this will set up, tear down, or update any
        // constraints to pin the view's size to it's sizeClass.
        switch (pinBoundsToSizeClass, sizeConstraints) {
        case (true, let constraints?):
            constraints.width.constant = sizeClass.size.width
            constraints.height.constant = sizeClass.size.height
        case (true, nil):
            sizeConstraints = (width: autoSetDimension(.width, toSize: sizeClass.size.width),
                               height: autoSetDimension(.height, toSize: sizeClass.size.height))
        case (false, _):
            if let sizeConstraints = sizeConstraints {
                NSLayoutConstraint.deactivate([sizeConstraints.width, sizeConstraints.height])
            }
            sizeConstraints = nil
        }

        super.updateConstraints()
    }

    override public func layoutSubviews() {
        super.layoutSubviews()

        // Let's update our badge if necessary before checking our invariants
        if let updatedBadge = preferredAssetFromBadgeProvider(), badgeImage != updatedBadge {
            badgeView.image = updatedBadge
        }

        // We have some assumptions about layout that adopters must conform to, let's assert those invariants
        checkLayoutInvariants()

        // Our subviews are always layed out with manual layout. Always aligned to the top left with the assumption
        // that our superview has us sized correctly.
        avatarView.frame = CGRect(origin: .zero, size: sizeClass.size)
        badgeView.frame = CGRect(origin: sizeClass.badgeOffset, size: sizeClass.badgeSize)

        switch shape {
        case .circular:
            avatarView.layer.cornerRadius = (avatarView.bounds.height / 2)
            avatarView.layer.masksToBounds = true
        case .rectangular:
            avatarView.layer.cornerRadius = 0
            avatarView.layer.masksToBounds = false
        }

        badgeView.isHidden = (badgeView.image == nil)
    }

    // MARK: - Subviews

    private var avatarView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFill
        view.layer.minificationFilter = .trilinear
        view.layer.magnificationFilter = .trilinear
        return view
    }()

    private var badgeView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        return view
    }()

    // MARK: - Private helpers

    func checkLayoutInvariants() {
        // This method is called during -layoutSubviews to verify some assumptions, namely:
        // - Our superview should have sized us to one of a few different sizes (this is checked after a constraint update pass)
        // - If we have a badge set, it should be one of our expected sizes

        owsAssertDebug(bounds.size == sizeClass.size, "Superview has sized \(self) incorrectly for size class \(sizeClass). " +
                       "Current size: \(bounds.size). Expected bounds: \(sizeClass.size)")

        if let badgeImage = badgeImage {
            owsAssertDebug(clipsToBounds == false, "Clip to bounds should be false. Badge art may extend outside of view bounds")
            owsAssertDebug(badgeImage.size == sizeClass.badgeSize, "Badge image dimensions incorrect. Badge size: \(badgeImage.size). " +
                           "Expected size: \(sizeClass.badgeSize)")
            owsAssertDebug(shape == .circular, "No current specs for badge placement of rectangular avatars.")
        }
    }

    func preferredAssetFromBadgeProvider() -> UIImage? {
        guard let badgeProvider = badgeProvider else { return nil }

        switch sizeClass.badgeSize {
        case .square(16): return Theme.isDarkThemeEnabled ? badgeProvider.dark16 : badgeProvider.light16
        case .square(24): return Theme.isDarkThemeEnabled ? badgeProvider.dark24 : badgeProvider.light24
        case .square(36): return Theme.isDarkThemeEnabled ? badgeProvider.dark36 : badgeProvider.light36
        default:
            owsFailDebug("Unrecognized badge size for \(sizeClass): \(sizeClass.badgeSize)")
            return nil
        }
    }
}

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
