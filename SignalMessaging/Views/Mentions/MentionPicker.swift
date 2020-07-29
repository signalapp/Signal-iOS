//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

class MentionPicker: UIView {
    let tableView = UITableView()
    let hairlineView = UIView()

    let mentionableUsers: [MentionableUser]
    struct MentionableUser {
        let address: SignalServiceAddress
        let username: String?
        let displayName: String
        let conversationColorName: ConversationColorName
    }

    lazy private(set) var filteredMentionableUsers = mentionableUsers

    static var contactsManager: OWSContactsManager { Environment.shared.contactsManager }
    static var databaseStorage: SDSDatabaseStorage { .shared }
    static var profileManager: OWSProfileManager { .shared() }

    let selectedAddressCallback: (SignalServiceAddress) -> Void

    required init(mentionableAddresses: [SignalServiceAddress], selectedAddressCallback: @escaping (SignalServiceAddress) -> Void) {
        mentionableUsers = Self.databaseStorage.uiRead { transaction in
            let sortedAddresses = Self.contactsManager.sortSignalServiceAddresses(
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
                    username: Self.profileManager.username(for: address, transaction: transaction),
                    displayName: Self.contactsManager.displayName(for: address, transaction: transaction),
                    conversationColorName: ConversationColorName(
                        rawValue: TSContactThread.conversationColorName(forContactAddress: address, transaction: transaction)
                    )
                )
            }
        }

        self.selectedAddressCallback = selectedAddressCallback

        super.init(frame: .zero)

        addSubview(tableView)
        tableView.autoPinEdgesToSuperviewEdges()

        tableView.delegate = self
        tableView.dataSource = self
        tableView.estimatedRowHeight = 48
        tableView.rowHeight = UITableView.automaticDimension
        tableView.separatorStyle = .none

        tableView.panGestureRecognizer.addTarget(self, action: #selector(handlePan))
        tableView.register(MentionableUserCell.self, forCellReuseIdentifier: MentionableUserCell.reuseIdentifier)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applyTheme),
            name: .ThemeDidChange,
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

    private lazy var tableViewHeightConstraint = tableView.autoSetDimension(.height, toSize: minimumTableHeight)
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
        let maximumContainerHeight = superview.height - (superview.height - frame.maxY)
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

            if let username = user.username {
                namesToCheck.append(username.lowercased())
            }

            for name in namesToCheck {
                guard name.hasPrefix(mentionText) else { continue }
                return true
            }

            return false
        }

        guard !filteredMentionableUsers.isEmpty else { return false }

        tableView.contentOffset.y = 0
        tableView.reloadData()

        var newHeight = min(maximumTableHeight, tableView.height)
        newHeight = max(minimumTableHeight, newHeight)

        tableViewHeightConstraint.constant = newHeight

        resetInteractiveTransition()

        return true
    }

    // MARK: - Interactive resize

    let maxAnimationDuration: TimeInterval = 0.2
    var startingHeight: CGFloat?
    var startingTranslation: CGFloat?

    @objc private func handlePan(_ sender: UIPanGestureRecognizer) {
        switch sender.state {
        case .began, .changed:
            guard beginInteractiveTransitionIfNecessary(sender),
                let startingHeight = startingHeight,
                let startingTranslation = startingTranslation else {
                    return resetInteractiveTransition()
            }

            // We're in an interactive transition, so don't let the scrollView scroll.
            tableView.contentOffset.y = 0
            tableView.showsVerticalScrollIndicator = false

            // We may have panned some distance if we were scrolling before we started
            // this interactive transition. Offset the translation we use to move the
            // view by whatever the translation was when we started the interactive
            // portion of the gesture.
            let translation = sender.translation(in: self).y - startingTranslation

            var newHeight = startingHeight - translation
            newHeight = min(newHeight, maximumTableHeight)

            // Scale the translation when below the desired range,
            // to produce an elastic feeling when you overscroll.
            if (newHeight < minimumTableHeight) {
                let scaledHeightChange = (minimumTableHeight - newHeight) / 3
                newHeight = minimumTableHeight - scaledHeightChange
            }

            // Update our height to reflect the new position
            tableViewHeightConstraint.constant = newHeight
            layoutIfNeeded()

        case .ended, .cancelled, .failed:
            defer { resetInteractiveTransition() }

            guard tableView.height < minimumTableHeight else { break }

            UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseOut, animations: {
                self.tableViewHeightConstraint.constant = self.minimumTableHeight
                self.layoutIfNeeded()
            }, completion: nil)
        default:
            resetInteractiveTransition()

            guard let startingHeight = startingHeight else { break }
            tableViewHeightConstraint.constant = startingHeight
        }
    }

    private func beginInteractiveTransitionIfNecessary(_ sender: UIPanGestureRecognizer) -> Bool {
        // If we're at the top of the scrollView, or the view is not
        // currently maximized, we want to do an interactive transition.

        guard tableView.height < maximumTableHeight || tableView.height > minimumTableHeight && tableView.contentOffset.y <= 0 else { return false }

        if startingTranslation == nil {
            startingTranslation = sender.translation(in: self).y
        }

        if startingHeight == nil {
            startingHeight = tableView.height
        }

        return true
    }

    private func resetInteractiveTransition() {
        startingTranslation = nil
        startingHeight = nil
        tableView.showsVerticalScrollIndicator = true
    }

    // MARK: -

    @objc private func applyTheme() {
        tableView.backgroundColor = Theme.backgroundColor
        hairlineView.backgroundColor = Theme.actionSheetHairlineColor
        tableView.reloadData()
    }
}

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

        userCell.configure(with: mentionableUser)

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

    static let avatarHeight: CGFloat = 28
    static let vSpacing: CGFloat = 10
    static let hSpacing: CGFloat = 12

    static var cellHeight: CGFloat {
        let cell = MentionableUserCell()
        cell.displayNameLabel.text = LocalizationNotNeeded("size")
        cell.displayNameLabel.sizeToFit()
        return max(avatarHeight, ceil(cell.displayNameLabel.height)) + vSpacing * 2
    }

    let displayNameLabel = UILabel()
    let usernameLabel = UILabel()
    let avatarImageView = AvatarImageView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        let avatarContainer = UIView()
        avatarContainer.addSubview(avatarImageView)
        avatarImageView.autoSetDimension(.width, toSize: Self.avatarHeight)
        avatarImageView.autoPinWidthToSuperview()
        avatarImageView.autoVCenterInSuperview()
        avatarImageView.autoMatch(.height, to: .height, of: avatarContainer, withOffset: 0, relation: .lessThanOrEqual)

        displayNameLabel.font = .ows_dynamicTypeBody2
        usernameLabel.font = .ows_dynamicTypeBody2

        let stackView = UIStackView(arrangedSubviews: [
            avatarContainer,
            displayNameLabel,
            usernameLabel,
            UIView.hStretchingSpacer()
        ])
        stackView.axis = .horizontal
        stackView.spacing = Self.hSpacing
        stackView.isUserInteractionEnabled = false
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.layoutMargins = UIEdgeInsets(top: Self.vSpacing, left: Self.hSpacing, bottom: Self.vSpacing, right: Self.hSpacing)

        contentView.addSubview(stackView)
        stackView.autoPinEdgesToSuperviewSafeArea()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with mentionableUser: MentionPicker.MentionableUser) {
        backgroundColor = Theme.backgroundColor
        displayNameLabel.textColor = Theme.primaryTextColor
        usernameLabel.textColor = Theme.secondaryTextAndIconColor

        displayNameLabel.text = mentionableUser.displayName

        if let username = mentionableUser.username {
            usernameLabel.isHidden = false
            usernameLabel.text = CommonFormats.formatUsername(username)
        } else {
            usernameLabel.isHidden = true
        }

        avatarImageView.image = OWSContactAvatarBuilder(
            address: mentionableUser.address,
            colorName: mentionableUser.conversationColorName,
            diameter: UInt(Self.avatarHeight)
        ).build()
    }
}
