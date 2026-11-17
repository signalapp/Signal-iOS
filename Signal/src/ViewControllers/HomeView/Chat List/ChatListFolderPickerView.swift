//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

struct ChatListFolderPickerState: Equatable {
    struct Tab: Hashable {
        let chatFolderId: UUID
        let name: String
    }

    let tabs: [Tab]
    let selectedChatFolderId: UUID?
    let unreadCountsByChatFolder: [UUID: UInt]

    init(viewInfo: CLVViewInfo, unreadCountsByChatFolder: [UUID: UInt]) {
        self.tabs = viewInfo.chatFolders.map { Tab(chatFolderId: $0.chatFolderId, name: $0.displayName) }
        self.unreadCountsByChatFolder = unreadCountsByChatFolder
        // nil means All Chats folder
        self.selectedChatFolderId = viewInfo.selectedChatFolder?.chatFolderId
            ?? viewInfo.chatFolders.first(where: { $0.folderType == .all })?.chatFolderId
    }
}

final class ChatListFolderPickerView: UIView {

    var didSelectFolder: ((UUID) -> Void)?
    var menuElementsForFolder: ((UUID) -> [UIMenuElement])?

    var isEnabled = true {
        didSet {
            isUserInteractionEnabled = isEnabled
            stackView.alpha = isEnabled ? 1 : 0.5
        }
    }

    private let containerView = UIView()
    private let scrollView = TabScrollView()
    private let stackView = UIStackView()

    private var tabs = [ChatListFolderPickerState.Tab]()
    private var selectedChatFolderId: UUID?
    private var unreadCountsByChatFolder = [UUID: UInt]()

    init() {
        super.init(frame: .zero)

        if #available(iOS 26, *) {
            let glassEffectView = UIVisualEffectView(effect: UIGlassEffect(style: .regular))
            glassEffectView.cornerConfiguration = .capsule()
            glassEffectView.clipsToBounds = true
            containerView.addSubview(glassEffectView)
            glassEffectView.autoPinEdgesToSuperviewEdges()
        } else {
            containerView.backgroundColor = .Signal.secondaryGroupedBackground
            containerView.layer.shadowColor = UIColor.black.cgColor
            containerView.layer.shadowOpacity = 0.08
            containerView.layer.shadowRadius = 8
            containerView.layer.shadowOffset = CGSize(width: 0, height: 2)
        }
        addSubview(containerView)

        insetsLayoutMarginsFromSafeArea = false
        updateLayoutMargins()
        containerView.autoPinEdgesToSuperviewMargins()

        scrollView.showsHorizontalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.alwaysBounceHorizontal = false
        containerView.addSubview(scrollView)
        scrollView.autoPinEdgesToSuperviewEdges()

        stackView.axis = .horizontal
        stackView.spacing = 0
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.insetsLayoutMarginsFromSafeArea = false
        stackView.layoutMargins = UIEdgeInsets(margin: 4)
        scrollView.addSubview(stackView)
        stackView.autoPinEdgesToSuperviewEdges()
        stackView.autoMatch(.height, to: .height, of: scrollView)
        // Fill width of picker if they don't scroll
        stackView.autoMatch(.width, to: .width, of: scrollView, withOffset: 0, relation: .greaterThanOrEqual)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        updateLayoutMargins()
    }

    // The picker sits inside the top safe area, so we can't simply preserve
    // the superview's safe areas, since we only want to inherit the horizontal.
    private func updateLayoutMargins() {
        layoutMargins = UIEdgeInsets(
            top: 4,
            left: 16 + safeAreaInsets.left,
            bottom: 8,
            right: 16 + safeAreaInsets.right,
        )
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        containerView.layer.cornerRadius = containerView.bounds.height / 2
        scrollView.layer.cornerRadius = containerView.layer.cornerRadius
        scrollView.clipsToBounds = true

        // If the tabs all fit, make them equal, otherwise self-size and scroll.
        let tabWidths = stackView.arrangedSubviews.map(\.intrinsicContentSize.width)
        let availableWidth = containerView.bounds.width - stackView.layoutMargins.totalWidth
        let distribution: UIStackView.Distribution
        if (tabWidths.max() ?? 0) * CGFloat(tabWidths.count) <= availableWidth {
            distribution = .fillEqually
        } else if tabWidths.reduce(0, +) <= availableWidth {
            distribution = .fillProportionally
        } else {
            distribution = .fill
        }
        if stackView.distribution != distribution {
            stackView.distribution = distribution
        }
    }

    func configure(state: ChatListFolderPickerState) {
        let tabsChanged = state.tabs != tabs
        let countsChanged = state.unreadCountsByChatFolder != unreadCountsByChatFolder
        let selectionChanged = state.selectedChatFolderId != selectedChatFolderId
        let wasSelectedTabVisible = selectedTabView.map {
            scrollView.bounds.contains(stackView.convert($0.frame, to: scrollView))
        } ?? false
        tabs = state.tabs
        unreadCountsByChatFolder = state.unreadCountsByChatFolder
        selectedChatFolderId = state.selectedChatFolderId

        if tabsChanged {
            stackView.removeAllSubviews()
            for tab in tabs {
                let button = FolderButton(tab: tab) { [weak self] in
                    self?.didSelectFolder?(tab.chatFolderId)
                }
                button.menu = UIMenu(children: [
                    UIDeferredMenuElement.uncached { [weak self] completion in
                        completion(self?.menuElementsForFolder?(tab.chatFolderId) ?? [])
                    },
                ])
                stackView.addArrangedSubview(button)
                button.autoMatch(
                    .width,
                    to: .width,
                    of: scrollView,
                    withOffset: -stackView.layoutMargins.totalWidth,
                    relation: .lessThanOrEqual,
                )
            }
        }
        updateButtons()

        if tabsChanged || countsChanged {
            setNeedsLayout()
        }

        if tabsChanged || selectionChanged {
            scrollSelectedTabToCenter(animated: !tabsChanged)
        } else if countsChanged, wasSelectedTabVisible {
            // Counts changing can update the width of the buttons
            layoutIfNeeded()
            if let selectedTabView {
                scrollView.scrollRectToVisible(stackView.convert(selectedTabView.frame, to: scrollView), animated: false)
            }
        }
    }

    private var folderButtons: [FolderButton] {
        stackView.arrangedSubviews.compactMap { $0 as? FolderButton }
    }

    private var selectedTabView: FolderButton? {
        folderButtons.first { $0.chatFolderId == selectedChatFolderId }
    }

    private func scrollSelectedTabToCenter(animated: Bool) {
        guard let selectedTab = selectedTabView else { return }
        layoutIfNeeded()
        let visibleWidth = scrollView.bounds.width
        let maxContentOffsetX = max(0, scrollView.contentSize.width - visibleWidth)
        let selectedTabMidX = stackView.convert(selectedTab.frame, to: scrollView).midX
        let contentOffsetX = (selectedTabMidX - visibleWidth / 2).clamp(0, maxContentOffsetX)
        let contentOffset = CGPoint(x: contentOffsetX, y: 0)

        if !animated || UIAccessibility.isReduceMotionEnabled {
            scrollView.setContentOffset(contentOffset, animated: false)
            return
        }

        let animator = UIViewPropertyAnimator(duration: 0.3, springDamping: 1, springResponse: 0.3)
        animator.isUserInteractionEnabled = true
        animator.isInterruptible = true
        animator.addAnimations {
            self.scrollView.contentOffset = contentOffset
        }
        animator.startAnimation()
    }

    private func updateButtons() {
        for button in folderButtons {
            button.update(
                isSelected: button.chatFolderId == selectedChatFolderId,
                unreadCount: unreadCountsByChatFolder[button.chatFolderId, default: 0],
            )
        }
    }
}

private final class FolderButton: UIButton {
    private static let badgeSpacing: CGFloat = 6

    private let badgeLabel = {
        let label = UILabel()
        label.backgroundColor = .Signal.accent
        label.textColor = .white
        label.textAlignment = .center
        label.clipsToBounds = true
        label.isUserInteractionEnabled = false
        label.isAccessibilityElement = false
        label.isHidden = true
        return label
    }()

    let chatFolderId: UUID
    private let name: String
    private var isSelectedFolder = false
    private var unreadCount: UInt = 0

    init(tab: ChatListFolderPickerState.Tab, onTap: @escaping () -> Void) {
        self.chatFolderId = tab.chatFolderId
        self.name = tab.name
        super.init(frame: .zero)
        configuration = .plain()
        addAction(
            UIAction { _ in
                onTap()
            },
            for: .touchUpInside,
        )

        addSubview(badgeLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(isSelected: Bool, unreadCount: UInt) {
        isSelectedFolder = isSelected
        self.unreadCount = unreadCount
        applyConfiguration()
    }

    override func updateConfiguration() {
        super.updateConfiguration()
        applyConfiguration()
    }

    private func applyConfiguration() {
        let badgeWidth = updateBadge()
        var configuration = configuration ?? .plain()
        configuration.title = name
        configuration.titleLineBreakMode = .byTruncatingTail
        configuration.titleTextAttributesTransformer = .defaultFont(.dynamicTypeSubheadlineClamped.semibold())
        configuration.baseForegroundColor = .Signal.label
        configuration.cornerStyle = .capsule
        configuration.background.backgroundColor = isSelectedFolder ? .Signal.secondaryFill : .clear
        configuration.contentInsets = NSDirectionalEdgeInsets(
            top: 6,
            leading: 16,
            bottom: 6,
            // Add to the insets to update the intrinsic size
            trailing: 16 + badgeWidth,
        )
        let insetsChanged = configuration.contentInsets != self.configuration?.contentInsets
        self.configuration = configuration
        if insetsChanged {
            invalidateIntrinsicContentSize()
        }
        accessibilityTraits = isSelectedFolder ? [.button, .selected] : .button
    }

    /// Returns the space needed for the badge after the title
    private func updateBadge() -> CGFloat {
        let count = unreadCount
        accessibilityValue = count > 0 ? count.formatted() : nil

        guard count > 0 else {
            badgeLabel.isHidden = true
            badgeLabel.text = nil
            return 0
        }

        badgeLabel.isHidden = false
        badgeLabel.font = .dynamicTypeCaption1Clamped
        badgeLabel.text = if count > 99 {
            OWSLocalizedString(
                "CHAT_FOLDERS_UNREAD_BADGE_OVERFLOW",
                comment: "Unread count shown on a chat folder tab when it has more than 99 unread messages or chats.",
            )
        } else {
            count.formatted()
        }
        let height = ceil(badgeLabel.font.lineHeight * 1.25)
        let width = max(height, badgeLabel.intrinsicContentSize.width + .ceilEven(height * 0.5))
        badgeLabel.bounds.size = CGSize(width: width, height: height)
        badgeLabel.layer.cornerRadius = height / 2
        setNeedsLayout()
        return Self.badgeSpacing + width
    }

    // UIButton.Configuration doesn't make it easy to add a view next to the
    // title, so we're manually positioning it instead
    override func layoutSubviews() {
        super.layoutSubviews()
        guard !badgeLabel.isHidden, let titleLabel else { return }
        let titleFrame = titleLabel.convert(titleLabel.bounds, to: self)
        let badgeSize = badgeLabel.bounds.size
        let badgeX = switch effectiveUserInterfaceLayoutDirection {
        case .rightToLeft: titleFrame.minX - Self.badgeSpacing - badgeSize.width
        case .leftToRight: titleFrame.maxX + Self.badgeSpacing
        @unknown default: titleFrame.maxX + Self.badgeSpacing
        }
        badgeLabel.frame = CGRect(
            origin: CGPoint(x: badgeX, y: titleFrame.midY - badgeSize.height / 2),
            size: badgeSize,
        )
    }
}

private final class TabScrollView: UIScrollView {
    /// Allows scrolling when you hold a press on a folder
    override func touchesShouldCancel(in view: UIView) -> Bool {
        return true
    }
}
