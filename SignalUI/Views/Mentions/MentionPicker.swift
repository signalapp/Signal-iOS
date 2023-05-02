//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging

public enum MentionPickerStyle {
    case `default`
    case composingAttachment
    case groupReply
}

class MentionPicker: UIView {
    private let tableView = UITableView()
    private let hairlineView = UIView()
    private let resizingScrollView = ResizingScrollView<UITableView>()
    private var blurView: UIVisualEffectView?

    let mentionableUsers: [MentionableUser]
    struct MentionableUser {
        let address: SignalServiceAddress
        let displayName: String
    }

    lazy private(set) var filteredMentionableUsers = mentionableUsers

    typealias Style = MentionPickerStyle

    let style: Style
    let selectedAddressCallback: (SignalServiceAddress) -> Void

    required init(
        mentionableAddresses: [SignalServiceAddress],
        style: Style,
        selectedAddressCallback: @escaping (SignalServiceAddress) -> Void
    ) {
        mentionableUsers = Self.databaseStorage.read { transaction in
            let sortedAddresses = Self.contactsManagerImpl.sortSignalServiceAddresses(
                mentionableAddresses,
                transaction: transaction
            )

            return sortedAddresses.compactMap { address in
                guard !address.isLocalAddress else {
                    owsFailDebug("Unexpectedly encountered local user in mention picker")
                    return nil
                }

                return MentionableUser(
                    address: address,
                    displayName: Self.contactsManager.displayName(for: address, transaction: transaction)
                )
            }
        }

        self.style = style
        self.selectedAddressCallback = selectedAddressCallback

        super.init(frame: .zero)

        backgroundColor = .clear

        addSubview(tableView)
        tableView.autoPinEdgesToSuperviewEdges()

        tableView.delegate = self
        tableView.dataSource = self
        tableView.estimatedRowHeight = cellHeight
        tableView.rowHeight = UITableView.automaticDimension
        tableView.separatorStyle = .none
        tableView.isScrollEnabled = false

        tableView.register(MentionableUserCell.self, forCellReuseIdentifier: MentionableUserCell.reuseIdentifier)

        resizingScrollView.resizingView = tableView
        resizingScrollView.delegate = self
        addSubview(resizingScrollView)
        resizingScrollView.autoPinEdgesToSuperviewEdges()
        tableView.autoMatch(.height, to: .height, of: resizingScrollView)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applyTheme),
            name: .themeDidChange,
            object: nil
        )

        addSubview(hairlineView)
        hairlineView.autoPinWidthToSuperview()
        hairlineView.autoPinEdge(.top, to: .top, of: tableView)
        hairlineView.autoSetDimension(.height, toSize: 1)

        applyTheme()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc
    public override var center: CGPoint {
        didSet {
            // iOS 15 layout changes introduce a crash where we re-enterantly perform
            // layout. A stopgap candidate fix may be to only refresh height constraints
            // if the center changes *significantly* (rather than any change at all)
            if !oldValue.fuzzyEquals(center, tolerance: 0.1) {
                resizingScrollView.refreshHeightConstraints()
            }
        }
    }

    private var cellHeight: CGFloat { MentionableUserCell.cellHeight }
    private var minimumTableHeight: CGFloat {
        let minimumTableHeight = filteredMentionableUsers.count < 5
            ? CGFloat(filteredMentionableUsers.count) * cellHeight
            : 4.5 * cellHeight
        return min(minimumTableHeight, maximumTableHeight)
    }
    private var maximumTableHeight: CGFloat {
        guard let superview = superview else { return CurrentAppContext().frame.height }
        superview.layoutIfNeeded()
        let maximumCellHeight = CGFloat(filteredMentionableUsers.count) * cellHeight
        let maximumContainerHeight = superview.height - (superview.height - frame.maxY) - superview.safeAreaInsets.top
        return min(maximumCellHeight, maximumContainerHeight)
    }

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

        resizingScrollView.refreshHeightConstraints()

        return true
    }

    // MARK: -

    @objc
    private func applyTheme() {
        switch style {
        case .composingAttachment:
            tableView.backgroundColor = UIColor.ows_gray95
            hairlineView.backgroundColor = .ows_gray65
        case .groupReply:
            blurView?.removeFromSuperview()
            blurView = nil

            if UIAccessibility.isReduceTransparencyEnabled {
                tableView.backgroundColor = Theme.darkThemeBackgroundColor
            } else {
                tableView.backgroundColor = .clear

                let blurView = UIVisualEffectView(effect: Theme.darkThemeBarBlurEffect)
                self.blurView = blurView
                insertSubview(blurView, belowSubview: tableView)
                blurView.autoPinEdgesToSuperviewEdges()
            }

            hairlineView.backgroundColor = .ows_gray75
        case .`default`:
            blurView?.removeFromSuperview()
            blurView = nil

            if UIAccessibility.isReduceTransparencyEnabled {
                tableView.backgroundColor = Theme.backgroundColor
            } else {
                tableView.backgroundColor = .clear

                let blurView = UIVisualEffectView(effect: Theme.barBlurEffect)
                self.blurView = blurView
                insertSubview(blurView, belowSubview: tableView)
                blurView.autoPinEdgesToSuperviewEdges()
            }

            hairlineView.backgroundColor = Theme.isDarkThemeEnabled ? .ows_gray75 : .ows_gray05
        }
        tableView.reloadData()
    }
}

extension MentionPicker: ResizingScrollViewDelegate {
    var resizingViewMinimumHeight: CGFloat { minimumTableHeight }

    var resizingViewMaximumHeight: CGFloat { maximumTableHeight }
}

// MARK: - Keyboard Interaction

extension MentionPicker {
    func highlightAndScrollToRow(_ row: Int, animated: Bool = true) {
        guard row >= 0 && row < filteredMentionableUsers.count else { return }

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
        guard let selectedIndex = tableView.indexPathForSelectedRow,
            let mentionableUser = filteredMentionableUsers[safe: selectedIndex.row] else { return }
        selectedAddressCallback(mentionableUser.address)
    }
}

// MARK: -

extension MentionPicker: UITableViewDelegate, UITableViewDataSource {
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

private class MentionableUserCell: UITableViewCell {
    static let reuseIdentifier = "MentionPickerCell"

    static let avatarSizeClass: ConversationAvatarView.Configuration.SizeClass = .thirtySix
    static let vSpacing: CGFloat = 10
    static let hSpacing: CGFloat = 12

    static var cellHeight: CGFloat {
        let cell = MentionableUserCell()
        cell.displayNameLabel.text = LocalizationNotNeeded("size")
        cell.displayNameLabel.sizeToFit()
        return max(CGFloat(avatarSizeClass.size.height), ceil(cell.displayNameLabel.height)) + vSpacing * 2
    }

    let displayNameLabel = UILabel()
    let avatarView = ConversationAvatarView(
        sizeClass: MentionableUserCell.avatarSizeClass,
        localUserDisplayMode: .asUser,
        useAutolayout: true)

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        backgroundColor = .clear
        selectedBackgroundView = UIView()

        let avatarContainer = UIView()
        avatarContainer.addSubview(avatarView)
        avatarView.autoPinWidthToSuperview()
        avatarView.autoVCenterInSuperview()
        avatarView.autoMatch(.height, to: .height, of: avatarContainer, withOffset: 0, relation: .lessThanOrEqual)

        displayNameLabel.font = .dynamicTypeBody2

        let stackView = UIStackView(arrangedSubviews: [
            avatarContainer,
            displayNameLabel,
            UIView.hStretchingSpacer()
        ])
        stackView.axis = .horizontal
        stackView.spacing = Self.hSpacing
        stackView.isUserInteractionEnabled = false
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.layoutMargins = UIEdgeInsets(top: Self.vSpacing, left: Self.hSpacing, bottom: Self.vSpacing, right: Self.hSpacing)

        contentView.addSubview(stackView)
        stackView.autoPinHeightToSuperview()
        stackView.autoPinEdge(toSuperviewSafeArea: .leading)
        stackView.autoPinEdge(toSuperviewSafeArea: .trailing)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with mentionableUser: MentionPicker.MentionableUser, style: MentionPicker.Style) {
        switch style {
        case .composingAttachment, .groupReply:
            displayNameLabel.textColor = Theme.darkThemePrimaryColor
            selectedBackgroundView?.backgroundColor = UIColor.white.withAlphaComponent(0.2)
        case .`default`:
            displayNameLabel.textColor = Theme.primaryTextColor
            selectedBackgroundView?.backgroundColor = Theme.cellSelectedColor
        }

        displayNameLabel.text = mentionableUser.displayName

        avatarView.updateWithSneakyTransactionIfNecessary { configuration in
            configuration.dataSource = .address(mentionableUser.address)
        }
    }
}
