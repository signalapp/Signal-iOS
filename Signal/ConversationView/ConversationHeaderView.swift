//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalUI

protocol ConversationHeaderViewDelegate: AnyObject {
    func didTapConversationHeaderView(_ conversationHeaderView: ConversationHeaderView)
    func didTapConversationHeaderViewAvatar(_ conversationHeaderView: ConversationHeaderView)
}

class ConversationHeaderView: UIView {

    weak var delegate: ConversationHeaderViewDelegate?

    var titleIcon: UIImage? {
        get {
            return titleIconView.image
        }
        set {
            titleIconView.image = newValue
            titleIconView.isHidden = newValue == nil
        }
    }

    let titleLabel: UILabel = {
        let label = UILabel()
        label.textColor = UIColor.Signal.label
        label.lineBreakMode = .byTruncatingTail
        label.font = .systemFont(ofSize: 17, weight: .semibold)
        label.setContentHuggingHigh()
        return label
    }()

    let subtitleLabel: UILabel = {
        let label = UILabel()
        label.textColor = .Signal.label
        label.lineBreakMode = .byTruncatingTail
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.setContentHuggingHigh()
        return label
    }()

    private let titleIconView: UIImageView = {
        let titleIconView = UIImageView()
        titleIconView.isHidden = true
        titleIconView.contentMode = .scaleAspectFit
        titleIconView.setCompressionResistanceHigh()
        return titleIconView
    }()
    private var titleIconSizeConstraint: NSLayoutConstraint!

    private var avatarSizeClass: ConversationAvatarView.Configuration.SizeClass {
        // One size for the navigation bar on iOS 26.
        guard #unavailable(iOS 26) else { return .forty }

        return traitCollection.verticalSizeClass == .compact && !UIDevice.current.isPlusSizePhone
        ? .twentyFour
        : .thirtySix
    }
    private(set) lazy var avatarView = ConversationAvatarView(
        sizeClass: avatarSizeClass,
        localUserDisplayMode: .noteToSelf)

    override init(frame: CGRect) {
        super.init(frame: frame)

        translatesAutoresizingMaskIntoConstraints = false

        let titleColumns = UIStackView(arrangedSubviews: [titleLabel, titleIconView])
        titleColumns.spacing = 5
        titleColumns.translatesAutoresizingMaskIntoConstraints = false
        // There is a strange bug where an initial height of 0
        // breaks the layout, so set an initial height.
        titleColumns.heightAnchor.constraint(greaterThanOrEqualToConstant: titleLabel.font.lineHeight.rounded(.up)).isActive = true

        let textRows = UIStackView(arrangedSubviews: [titleColumns, subtitleLabel])
        textRows.axis = .vertical
        textRows.alignment = .leading
        textRows.distribution = .fillProportionally

        let rootStack = UIStackView(arrangedSubviews: [ avatarView, textRows ])
        rootStack.directionalLayoutMargins = .init(hMargin: 0, vMargin: 4)
        if #available(iOS 26, *) {
            // Default iOS 26 spacing between round back button and this view's leading edge is 12 pts.
            // We want 16 pts between back button and profile picture.
            rootStack.directionalLayoutMargins.leading = 4
        }
        rootStack.isLayoutMarginsRelativeArrangement = true
        rootStack.axis = .horizontal
        rootStack.alignment = .center
        // Larger profile picture on iOS 26 requires larger padding on both sides.
        rootStack.spacing = if #available(iOS 26, *) { 12 } else { 8 }

        addSubview(rootStack)
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        titleIconView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            titleIconView.heightAnchor.constraint(equalToConstant: 16),
            titleIconView.widthAnchor.constraint(equalTo: titleIconView.heightAnchor),

            rootStack.topAnchor.constraint(equalTo: topAnchor),
            rootStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            rootStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            rootStack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        // Embed a small glass view behind the avatar so that it's never visible to the user.
        // Glass views react to content underneath and update appearance (light / dark)
        // automatically. Using newer API for detecting trait collection changes it's now
        // possible to attach a small handler that will force UILabels to have
        // the same light or dark style as the glass view.
        if #available(iOS 26, *) {
            let glassTrackingView = UIVisualEffectView(effect: UIGlassEffect(style: .regular))
            rootStack.insertSubview(glassTrackingView, at: 0)
            glassTrackingView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                glassTrackingView.widthAnchor.constraint(equalToConstant: 10),
                glassTrackingView.heightAnchor.constraint(equalToConstant: 10),
                glassTrackingView.centerXAnchor.constraint(equalTo: avatarView.centerXAnchor),
                glassTrackingView.centerYAnchor.constraint(equalTo: avatarView.centerYAnchor),
            ])

            glassTrackingView.contentView.registerForTraitChanges(
                [ UITraitUserInterfaceStyle.self ],
                handler: { [weak textRows] (view: UIView, _) in
                    textRows?.overrideUserInterfaceStyle = view.traitCollection.userInterfaceStyle
                }
            )
        }

        if #available(iOS 26, *) {
            heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        }

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(didTapView))
        rootStack.addGestureRecognizer(tapGesture)
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(threadViewModel: ThreadViewModel) {
        avatarView.updateWithSneakyTransactionIfNecessary { config in
            config.dataSource = .thread(threadViewModel.threadRecord)
            config.storyConfiguration = .autoUpdate()
            config.applyConfigurationSynchronously()
        }
    }

    override var intrinsicContentSize: CGSize {
        // Grow to fill as much of the navbar as possible.
        return .init(width: .greatestFiniteMagnitude, height: UIView.noIntrinsicMetric)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        // One size for the navigation bar on iOS 26.
        guard #unavailable(iOS 26) else { return }

        guard traitCollection.verticalSizeClass != previousTraitCollection?.verticalSizeClass else { return }
        avatarView.updateWithSneakyTransactionIfNecessary { config in
            config.sizeClass = avatarSizeClass
        }
    }

    // MARK: Delegate Methods

    @objc
    private func didTapView(tapGesture: UITapGestureRecognizer) {
        guard tapGesture.state == .recognized else {
            return
        }

        if avatarView.bounds.contains(tapGesture.location(in: avatarView)) {
            self.delegate?.didTapConversationHeaderViewAvatar(self)
        } else {
            self.delegate?.didTapConversationHeaderView(self)
        }
    }
}
