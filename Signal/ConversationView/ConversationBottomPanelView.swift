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

    /// Subclasses must constrain their content to this layout guide.
    let contentLayoutGuide = UILayoutGuide()

    private lazy var backgroundView = UIVisualEffectView(effect: UIBlurEffect(style: .prominent))

    override init(frame: CGRect) {
        super.init(frame: frame)

        directionalLayoutMargins = .init(hMargin: 16, vMargin: 16)

        addLayoutGuide(contentLayoutGuide)

        addSubview(backgroundView)
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
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
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension ConversationBottomPanelView: ConversationBottomBar {
    var shouldAttachToKeyboardLayoutGuide: Bool { false }
}
