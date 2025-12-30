//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import SignalServiceKit

public enum MentionPickerStyle {
    case `default`
    case composingAttachment
    case groupReply
}

class MentionPicker: UIView {

    typealias Style = MentionPickerStyle

    let style: Style
    let selectedAddressCallback: (SignalServiceAddress) -> Void

    init(
        mentionableAcis: [Aci],
        style: Style,
        selectedAddressCallback: @escaping (SignalServiceAddress) -> Void,
    ) {
        let databaseStorage = SSKEnvironment.shared.databaseStorageRef
        mentionableUsers = databaseStorage.read { transaction in
            let sortedAddresses = SSKEnvironment.shared.contactManagerImplRef.sortSignalServiceAddresses(
                mentionableAcis.map({ SignalServiceAddress($0) }),
                transaction: transaction,
            )

            return sortedAddresses.compactMap { address in
                guard !address.isLocalAddress else {
                    owsFailDebug("Unexpectedly encountered local user in mention picker")
                    return nil
                }

                return MentionableUser(
                    address: address,
                    displayName: SSKEnvironment.shared.contactManagerRef.displayName(for: address, tx: transaction).resolvedValue(),
                )
            }
        }

        self.style = style
        self.selectedAddressCallback = selectedAddressCallback

        super.init(frame: .zero)

        layoutMargins = .zero

        let useVisualEffectViewBackground: Bool
        let useGlassBackground: Bool

        switch style {
        case .composingAttachment:
            overrideUserInterfaceStyle = .dark
            tableView.backgroundColor = UIColor.ows_gray95

            useVisualEffectViewBackground = false
            useGlassBackground = false

        case .groupReply:
            overrideUserInterfaceStyle = .dark

            useVisualEffectViewBackground = true
            useGlassBackground = false

        case .default:
            useVisualEffectViewBackground = true
            if #available(iOS 26, *), BuildFlags.iOS26SDKIsAvailable {
                useGlassBackground = true
            } else {
                useGlassBackground = false
            }
        }

        if useVisualEffectViewBackground {
#if compiler(>=6.2)
            // Glass background, rounded corners, horizontal insets.
            if #available(iOS 26, *), useGlassBackground {
                let glassEffectView = UIVisualEffectView(effect: backgroundViewVisualEffect())
                glassEffectView.clipsToBounds = true
                glassEffectView.cornerConfiguration = .uniformCorners(radius: .fixed(34))

                backgroundView = glassEffectView

                tableView.cornerConfiguration = .uniformCorners(radius: .fixed(34))
                tableView.contentInset.top = 10
                tableView.contentInset.bottom = 10

                directionalLayoutMargins = .init(hMargin: OWSTableViewController2.cellHInnerMargin, vMargin: 0)
            }
#endif

            // Blur background.
            if backgroundView == nil {
                if UIAccessibility.isReduceTransparencyEnabled {
                    tableView.backgroundColor = overrideUserInterfaceStyle == .dark
                        ? Theme.darkThemeBackgroundColor
                        : Theme.backgroundColor
                } else {
                    backgroundView = UIVisualEffectView(effect: backgroundViewVisualEffect())
                }
            }

            if let backgroundView {
                backgroundView.translatesAutoresizingMaskIntoConstraints = false
                addSubview(backgroundView)
                NSLayoutConstraint.activate([
                    backgroundView.topAnchor.constraint(equalTo: topAnchor),
                    backgroundView.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
                    backgroundView.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
                    backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),
                ])
            }
        }

        if let backgroundView {
            backgroundView.contentView.addSubview(tableView)
        } else {
            addSubview(tableView)
        }
        tableView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: topAnchor),
            tableView.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        // Hairline for when there's no glass background.
        if !useGlassBackground {
            let hairlineView = UIView()
            switch style {
            case .composingAttachment:
                hairlineView.backgroundColor = .ows_gray65

            case .groupReply, .default:
                hairlineView.backgroundColor = UIColor { traitCollection in
                    traitCollection.userInterfaceStyle == .dark ? UIColor.ows_gray75 : UIColor.ows_gray05
                }
            }
            hairlineView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(hairlineView)
            NSLayoutConstraint.activate([
                hairlineView.topAnchor.constraint(equalTo: tableView.topAnchor),
                hairlineView.leadingAnchor.constraint(equalTo: leadingAnchor),
                hairlineView.trailingAnchor.constraint(equalTo: trailingAnchor),
                hairlineView.heightAnchor.constraint(equalToConstant: 1),
            ])

            self.hairlineView = hairlineView
        }

        // Setup height constraint for the container view.
        heightConstraint = tableView.heightAnchor.constraint(equalToConstant: 0)
        heightConstraint.priority = .defaultHigh
        heightConstraint.isActive = true
        updateHeightConstraint(to: minimumHeight())
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        updateHeightIfNeeded()
        DispatchQueue.main.async {
            self.updateHeightIfNeeded()
        }
    }

    // MARK: - Layout

    // `nil` if "Reduce Transparency" is enabled on iOS 15-18.
    private var backgroundView: UIVisualEffectView?

    private func backgroundViewVisualEffect() -> UIVisualEffect? {
#if compiler(>=6.2)
        if #available(iOS 26.1, *) {
            let glassEffect = UIGlassEffect(style: .regular)
            // Copy from ConversationInputToolbar.
            glassEffect.tintColor = UIColor { traitCollection in
                if traitCollection.userInterfaceStyle == .dark {
                    return UIColor(white: 0, alpha: 0.2)
                }
                return UIColor(white: 1, alpha: 0.12)
            }
            return glassEffect
        }
        // 26.0 would still use a panel with rounded corners, but with blur effect instead of glass.
        // This is because on 26.0 `UIGlassEffect` can't "dematerialize" due to UIKit bug.
        if #available(iOS 26, *) {
            return UIBlurEffect(style: .systemThinMaterial)
        }
#endif

        guard !UIAccessibility.isReduceTransparencyEnabled else { return nil }

        let blurEffect = overrideUserInterfaceStyle == .dark ? Theme.darkThemeBarBlurEffect : Theme.barBlurEffect
        return blurEffect
    }

    private lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .plain)
        tableView.delegate = self
        tableView.dataSource = self
        tableView.estimatedRowHeight = MentionableUserCell.cellHeight
        tableView.rowHeight = UITableView.automaticDimension
        tableView.separatorStyle = .none
        tableView.backgroundColor = .clear
        tableView.register(MentionableUserCell.self, forCellReuseIdentifier: MentionableUserCell.reuseIdentifier)
        return tableView
    }()

    private var hairlineView: UIView?

    private var currentHeight: CGFloat = 0

    private var heightConstraint: NSLayoutConstraint!

    private var isUpdatingHeight = false

    private var isExpanded = false

    private func updateHeightConstraint(to height: CGFloat) {
        let constrainedHeight = height.clamp(minimumHeight(), maximumHeight())

        guard constrainedHeight != currentHeight else { return }

        heightConstraint.constant = constrainedHeight
        currentHeight = constrainedHeight

        isUpdatingHeight = true
        UIView.animate(
            withDuration: 0.25,
            animations: {
                self.superview?.layoutIfNeeded()
            },
            completion: { _ in
                self.isUpdatingHeight = false
                self.lastContentOffset = self.tableView.contentOffset.y
            },
        )
    }

    func updateHeightIfNeeded() {
        let targetHeight = isExpanded ? maximumHeight() : minimumHeight()
        updateHeightConstraint(to: targetHeight)
    }

    private func expandTableView() {
        guard !isExpanded else { return }

        isExpanded = true
        let targetHeight = maximumHeight()
        updateHeightConstraint(to: targetHeight)
    }

    private func collapseTableView() {
        guard isExpanded else { return }

        isExpanded = false
        let targetHeight = minimumHeight()
        updateHeightConstraint(to: targetHeight)
    }

    private func minimumHeight() -> CGFloat {
        let cellHeight = MentionableUserCell.cellHeight
        let minimumHeight = filteredMentionableUsers.count < 5
            ? CGFloat(filteredMentionableUsers.count) * cellHeight
            : 4.5 * cellHeight
        return minimumHeight + tableView.contentInset.totalHeight
    }

    private func maximumHeight() -> CGFloat {
        var maximumContainerHeight = 0.5 * CurrentAppContext().frame.height
        if let superview, frame.size.height > 0 {
            maximumContainerHeight = frame.maxY - superview.safeAreaInsets.top
        }
        let maximumContentHeight = CGFloat(filteredMentionableUsers.count) * MentionableUserCell.cellHeight + tableView.contentInset.totalHeight
        return min(maximumContentHeight, maximumContainerHeight)
    }

    // MARK: - Animations

    // Make sure to match parementers in ConversationInputToolbar.StickerLayout.
    private static func animator() -> UIViewPropertyAnimator {
        return UIViewPropertyAnimator(
            duration: 0.35,
            springDamping: 1,
            springResponse: 0.35,
        )
    }

    // Make sure to match parementers in ConversationInputToolbar.StickerLayout.
    private static var animationTransform: CGAffineTransform {
        guard #available(iOS 26, *), BuildFlags.iOS26SDKIsAvailable else { return .identity }
        return .scale(0.9)
    }

    func prepareToAnimateIn() {
        if let backgroundView {
            backgroundView.effect = nil
        }
        tableView.alpha = 0
        hairlineView?.alpha = 0
        transform = MentionPicker.animationTransform
    }

    func animateIn() {
        let animator = MentionPicker.animator()
        animator.addAnimations {
            self.transform = .identity

            if
                let backgroundView = self.backgroundView,
                let backgroundViewEffect = self.backgroundViewVisualEffect()
            {
                backgroundView.effect = backgroundViewEffect
            }

            self.tableView.alpha = 1
            self.hairlineView?.alpha = 1
        }
        animator.startAnimation()
    }

    func animateOut(completion: @escaping (UIViewAnimatingPosition) -> Void) {
        let animator = MentionPicker.animator()
        animator.addAnimations {
            self.transform = MentionPicker.animationTransform

            if let backgroundView = self.backgroundView {
                backgroundView.effect = nil
            }

            self.tableView.alpha = 0
            self.hairlineView?.alpha = 0
        }
        animator.addCompletion(completion)
        animator.startAnimation()
    }

    // MARK: - Scroll Handling

    private var lastContentOffset: CGFloat = 0

    private func handleScroll(_ scrollView: UIScrollView) {
        guard !isUpdatingHeight else { return }

        let currentOffset = scrollView.contentOffset.y
        let offsetDifference = currentOffset - lastContentOffset

        let scrollThreshold: CGFloat = 40

        guard abs(offsetDifference) > scrollThreshold else { return }

        if offsetDifference > 0, !isExpanded {
            expandTableView()
        } else if isExpanded, currentOffset < -(scrollThreshold + tableView.contentInset.top) {
            collapseTableView()
        }
        lastContentOffset = currentOffset
    }

    // MARK: - User Matching

    struct MentionableUser {
        let address: SignalServiceAddress
        let displayName: String
    }

    private let mentionableUsers: [MentionableUser]

    private(set) lazy var filteredMentionableUsers = mentionableUsers

    /// Used to update the filtered list of users for display.
    /// If the mention text results in no users remaining, returns
    /// false so the caller can dismiss the picker.
    func mentionTextChanged(_ mentionText: String) -> Bool {
        // When the mention text changes, we need to re-examine which
        // users to suggest. We show any user who any word of their name
        // starts with the mention text. e.g. "Alice Bob" would show up
        // if you typed @al or @bo. We also allow typing through spaces,
        // so @alicebo would show "Alice Bob"

        filteredMentionableUsers = mentionableUsers.filter { user in
            let mentionText = mentionText.lowercased()

            var namesToCheck = user.displayName.components(separatedBy: " ").map { $0.lowercased() }

            let concatenatedDisplayName = user.displayName.replacingOccurrences(of: " ", with: "").lowercased()
            namesToCheck.append(concatenatedDisplayName)

            for name in namesToCheck {
                guard name.hasPrefix(mentionText) else { continue }
                return true
            }

            return false
        }

        guard !filteredMentionableUsers.isEmpty else { return false }

        tableView.reloadData()

        updateHeightIfNeeded()

        return true
    }
}

// MARK: - Keyboard Interaction

extension MentionPicker {

    func highlightAndScrollToRow(_ row: Int, animated: Bool = true) {
        guard row >= 0, row < filteredMentionableUsers.count else { return }

        tableView.selectRow(at: IndexPath(row: row, section: 0), animated: animated, scrollPosition: .none)
        tableView.scrollToRow(at: IndexPath(row: row, section: 0), at: .none, animated: animated)
    }

    func didTapUpArrow() {
        guard !filteredMentionableUsers.isEmpty else { return }

        var nextRow = filteredMentionableUsers.count - 1

        if let selectedIndex = tableView.indexPathForSelectedRow {
            nextRow = selectedIndex.row - 1
            if nextRow < 0 { nextRow = filteredMentionableUsers.count - 1 }
        }

        highlightAndScrollToRow(nextRow)
    }

    func didTapDownArrow() {
        guard !filteredMentionableUsers.isEmpty else { return }

        var nextRow = 0

        if let selectedIndex = tableView.indexPathForSelectedRow {
            nextRow = selectedIndex.row + 1
            if nextRow >= filteredMentionableUsers.count { nextRow = 0 }
        }

        highlightAndScrollToRow(nextRow)
    }

    func didTapReturn() {
        selectHighlightedRow()
    }

    func didTapTab() {
        selectHighlightedRow()
    }

    func selectHighlightedRow() {
        guard
            let selectedIndex = tableView.indexPathForSelectedRow,
            let mentionableUser = filteredMentionableUsers[safe: selectedIndex.row] else { return }
        selectedAddressCallback(mentionableUser.address)
    }
}

// MARK: -

extension MentionPicker: UITableViewDelegate, UITableViewDataSource {

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView.isTracking else { return }
        handleScroll(scrollView)
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        lastContentOffset = scrollView.contentOffset.y
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return filteredMentionableUsers.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: MentionableUserCell.reuseIdentifier, for: indexPath)

        guard let userCell = cell as? MentionableUserCell else {
            owsFailDebug("unexpected cell type")
            return cell
        }

        guard let mentionableUser = filteredMentionableUsers[safe: indexPath.row] else {
            owsFailDebug("missing mentionable user")
            return cell
        }

        userCell.configure(with: mentionableUser, style: style)

        return userCell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let mentionableUser = filteredMentionableUsers[safe: indexPath.row] else {
            return owsFailDebug("missing mentionable user")
        }

        selectedAddressCallback(mentionableUser.address)
    }
}

// MARK: -

private class MentionableUserCell: UITableViewCell {

    static let reuseIdentifier = "MentionPickerCell"

    private static let avatarSizeClass: ConversationAvatarView.Configuration.SizeClass = .thirtySix

    static var cellHeight: CGFloat {
        let cell = MentionableUserCell()
        cell.displayNameLabel.text = LocalizationNotNeeded("size")
        let cellSize = cell.systemLayoutSizeFitting(
            CGSize(width: 300, height: CGFloat.greatestFiniteMagnitude),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel,
        )
        return cellSize.height
    }

    private let displayNameLabel: UILabel = {
        let label = UILabel()
        label.textColor = .Signal.label
        label.font = .dynamicTypeBody
        return label
    }()

    private let avatarView = ConversationAvatarView(
        sizeClass: MentionableUserCell.avatarSizeClass,
        localUserDisplayMode: .asUser,
        useAutolayout: true,
    )

    private static let vMargin: CGFloat = 10
    private static let hMargin: CGFloat = 2 * vMargin

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        let avatarContainer = UIView()
        avatarContainer.addSubview(avatarView)
        avatarView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            avatarView.widthAnchor.constraint(equalToConstant: Self.avatarSizeClass.size.width),
            avatarView.heightAnchor.constraint(equalToConstant: Self.avatarSizeClass.size.height),

            avatarView.topAnchor.constraint(greaterThanOrEqualTo: avatarContainer.topAnchor),
            avatarView.centerYAnchor.constraint(equalTo: avatarContainer.centerYAnchor),
            avatarView.leadingAnchor.constraint(equalTo: avatarContainer.leadingAnchor),
            avatarView.trailingAnchor.constraint(equalTo: avatarContainer.trailingAnchor),
        ])

        let stackView = UIStackView(arrangedSubviews: [avatarContainer, displayNameLabel])
        stackView.axis = .horizontal
        stackView.spacing = 12
        stackView.isUserInteractionEnabled = false
        stackView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Self.vMargin),
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Self.hMargin),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Self.hMargin),
            stackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -Self.vMargin),
        ])
    }

    override func updateConfiguration(using state: UICellConfigurationState) {
        var configuration = UIBackgroundConfiguration.clear()
        if state.isSelected || state.isHighlighted {
            configuration.backgroundColor = .Signal.primaryFill
            if #available(iOS 26, *), BuildFlags.iOS26SDKIsAvailable {
                configuration.backgroundInsets = .init(hMargin: 0.5 * Self.hMargin, vMargin: 0)
                configuration.cornerRadius = 50
            }
        }
        backgroundConfiguration = configuration
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with mentionableUser: MentionPicker.MentionableUser, style: MentionPicker.Style) {
        displayNameLabel.text = mentionableUser.displayName

        avatarView.updateWithSneakyTransactionIfNecessary { configuration in
            configuration.dataSource = .address(mentionableUser.address)
        }
    }
}
