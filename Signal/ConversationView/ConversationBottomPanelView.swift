//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalUI

class ConversationBottomPanelView: UIView {

    /// Subclasses must add content here.
    var contentView: UIView {
        backgroundView.contentView
    }

    /// Sublasses can opt out of using glass panel background with double margins.
    @available(iOS 26, *)
    open var useGlassPanel: Bool {
        true
    }

    /// Subclasses must constrain their content to this layout guide.
    let contentLayoutGuide = UILayoutGuide()

    private var backgroundViewEffect: UIVisualEffect {
        if UIAccessibility.isReduceTransparencyEnabled {
            return UIBlurEffect(style: .systemThinMaterial)
        }
        guard #available(iOS 26, *), useGlassPanel else {
            return Theme.barBlurEffect
        }
        // Same as in ConversationInputToolbar.
        let glassEffect = UIGlassEffect(style: .regular)
        glassEffect.tintColor = .Signal.glassBackgroundTint
        glassEffect.isInteractive = true
        return glassEffect
    }

    private lazy var backgroundView = UIVisualEffectView(effect: backgroundViewEffect)

    // These are constraints defining how much is glass background inset
    // relative to view's leading, trailing and bottom edges.
    // The idea is to update those at run time to ensure that glass panel
    // has equal space on the sides and on the bottom (concentric corners appearance).
    private var backgroundViewLeading: NSLayoutConstraint?
    private var backgroundViewTrailing: NSLayoutConstraint?
    private var backgroundViewBottom: NSLayoutConstraint?

    override init(frame: CGRect) {
        super.init(frame: frame)

        directionalLayoutMargins = .init(hMargin: 16, vMargin: 16)

        addLayoutGuide(contentLayoutGuide)

        addSubview(backgroundView)
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        if #available(iOS 26, *), useGlassPanel {
            // Glass container is transparent and can be constrained to safe area edges.
            let glassContainerView = UIVisualEffectView(effect: UIGlassContainerEffect())
            addSubview(glassContainerView)
            glassContainerView.translatesAutoresizingMaskIntoConstraints = false

            backgroundView.clipsToBounds = true
            backgroundView.cornerConfiguration = .uniformBottomRadius(
                .containerConcentric(minimum: 26),
                topLeftRadius: .fixed(26),
                topRightRadius: .fixed(26),
            )
            glassContainerView.contentView.addSubview(backgroundView)
            backgroundViewLeading = backgroundView.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor)
            backgroundViewTrailing = backgroundView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor)
            backgroundViewBottom = backgroundView.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor)

            // This defines how much content is inset relative to glass panel's edges.
            let contentInsets = NSDirectionalEdgeInsets(hMargin: 16, vMargin: 12)

            addConstraints([
                glassContainerView.topAnchor.constraint(equalTo: topAnchor),
                glassContainerView.leadingAnchor.constraint(equalTo: leadingAnchor),
                glassContainerView.trailingAnchor.constraint(equalTo: trailingAnchor),
                glassContainerView.bottomAnchor.constraint(equalTo: bottomAnchor),

                // Whole `ConversationBottomPanelView` is pinned to the bottom
                // so fixed top margin is fine.
                backgroundView.topAnchor.constraint(
                    equalTo: topAnchor,
                    constant: 8, // leave some space at the top for glass panel's shadow
                ),
                backgroundViewLeading!,
                backgroundViewTrailing!,
                backgroundViewBottom!,

                // `contentLayoutGuide` will have fixed insets relative to the glass panel.
                contentLayoutGuide.topAnchor.constraint(
                    equalTo: backgroundView.topAnchor,
                    constant: contentInsets.top,
                ),
                contentLayoutGuide.leadingAnchor.constraint(
                    equalTo: backgroundView.leadingAnchor,
                    constant: contentInsets.leading,
                ),
                contentLayoutGuide.trailingAnchor.constraint(
                    equalTo: backgroundView.trailingAnchor,
                    constant: -contentInsets.trailing,
                ),
                contentLayoutGuide.bottomAnchor.constraint(
                    equalTo: backgroundView.bottomAnchor,
                    constant: -contentInsets.bottom,
                ),
            ])

            // Make sure to call this in `init` to establish decent insets
            // if safe area insets won't ever change (eg home button iPhones).
            updateBackgroundPanelConstraints()
        } else {
            addConstraints([
                backgroundView.topAnchor.constraint(equalTo: topAnchor),
                backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
                backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
                backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),

                contentLayoutGuide.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor),
                contentLayoutGuide.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
                contentLayoutGuide.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
                contentLayoutGuide.bottomAnchor.constraint(
                    equalTo: safeAreaLayoutGuide.bottomAnchor,
                    constant: UIDevice.current.hasIPhoneXNotch ? 0 : -12,
                ),
            ])

            // Alter the visual effect view's tint to match our background color
            // so the bottom panel, when over a solid color background matching UIColor.Signal.background,
            // exactly matches the background color. This is brittle, but there is no way to get
            // this behavior from UIVisualEffectView otherwise.
            if
                !UIAccessibility.isReduceTransparencyEnabled,
                let tintingView = backgroundView.subviews.first(where: {
                    String(describing: type(of: $0)) == "_UIVisualEffectSubview"
                })
            {
                tintingView.backgroundColor = UIColor.Signal.background.withAlphaComponent(OWSNavigationBar.backgroundBlurMutingFactor)
            }
        }
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()

        updateBackgroundPanelConstraints()
    }

    private func updateBackgroundPanelConstraints() {
        guard let backgroundViewLeading, let backgroundViewTrailing, let backgroundViewBottom else { return }

        var margin = safeAreaInsets.bottom

        guard margin < 35 else { return }

        if margin.isZero {
            margin = 8
        }

        backgroundViewLeading.constant = margin
        backgroundViewTrailing.constant = -margin
        backgroundViewBottom.constant = safeAreaInsets.bottom > 0 ? 0 : margin
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension ConversationBottomPanelView: ConversationBottomBar {
    var shouldAttachToKeyboardLayoutGuide: Bool { false }
}
