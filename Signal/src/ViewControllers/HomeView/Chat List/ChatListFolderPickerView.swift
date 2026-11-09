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

    init(viewInfo: CLVViewInfo) {
        self.tabs = viewInfo.chatFolders.map { Tab(chatFolderId: $0.chatFolderId, name: $0.displayName) }
        // nil means All Chats folder
        self.selectedChatFolderId = viewInfo.selectedChatFolder?.chatFolderId
            ?? viewInfo.chatFolders.first(where: { $0.folderType == .all })?.chatFolderId
    }
}

final class ChatListFolderPickerView: UIView {

    var didSelectFolder: ((UUID) -> Void)?

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

    init() {
        super.init(frame: .zero)

        containerView.backgroundColor = .Signal.secondaryGroupedBackground
        containerView.layer.shadowColor = UIColor.black.cgColor
        containerView.layer.shadowOpacity = 0.08
        containerView.layer.shadowRadius = 8
        containerView.layer.shadowOffset = CGSize(width: 0, height: 2)
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
        let availableWidth = scrollView.bounds.width - stackView.layoutMargins.totalWidth
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
        let selectionChanged = state.selectedChatFolderId != selectedChatFolderId
        tabs = state.tabs
        selectedChatFolderId = state.selectedChatFolderId

        if tabsChanged {
            stackView.removeAllSubviews()
            for tab in tabs {
                let button = buildButton(for: tab)
                stackView.addArrangedSubview(button)
                button.autoMatch(
                    .width,
                    to: .width,
                    of: scrollView,
                    withOffset: -stackView.layoutMargins.totalWidth,
                    relation: .lessThanOrEqual,
                )
            }
            setNeedsLayout()
        }
        updateButtons()

        if tabsChanged || selectionChanged {
            scrollSelectedTabToCenter(animated: !tabsChanged)
        }
    }

    private func scrollSelectedTabToCenter(animated: Bool) {
        guard
            let index = tabs.firstIndex(where: { $0.chatFolderId == selectedChatFolderId }),
            let selectedTab = stackView.arrangedSubviews[safe: index]
        else {
            return
        }
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

    private func buildButton(for tab: ChatListFolderPickerState.Tab) -> UIButton {
        let button = UIButton(
            configuration: .plain(),
            primaryAction: UIAction { [weak self] _ in
                self?.didSelectFolder?(tab.chatFolderId)
            },
        )
        button.configurationUpdateHandler = { [weak self] button in
            let isSelected = self?.selectedChatFolderId == tab.chatFolderId
            var configuration = button.configuration ?? .plain()
            configuration.title = tab.name
            configuration.titleLineBreakMode = .byTruncatingTail
            configuration.titleTextAttributesTransformer = .defaultFont(.dynamicTypeSubheadlineClamped.semibold())
            configuration.baseForegroundColor = .Signal.label
            configuration.cornerStyle = .capsule
            configuration.background.backgroundColor = isSelected ? .Signal.secondaryFill : .clear
            configuration.contentInsets = NSDirectionalEdgeInsets(hMargin: 16, vMargin: 10)
            button.configuration = configuration
            button.accessibilityTraits = isSelected ? [.button, .selected] : .button
        }
        return button
    }

    private func updateButtons() {
        for case let button as UIButton in stackView.arrangedSubviews {
            button.setNeedsUpdateConfiguration()
        }
    }
}

private final class TabScrollView: UIScrollView {
    /// Allows scrolling when you hold a press on a folder
    override func touchesShouldCancel(in view: UIView) -> Bool {
        return true
    }
}
