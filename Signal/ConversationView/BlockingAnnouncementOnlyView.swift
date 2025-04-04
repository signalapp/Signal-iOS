//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class BlockingAnnouncementOnlyView: UIStackView {

    private let thread: TSThread
    private let forceDarkMode: Bool

    private weak var fromViewController: UIViewController?

    convenience init(threadViewModel: ThreadViewModel, fromViewController: UIViewController, forceDarkMode: Bool = false) {
        self.init(thread: threadViewModel.threadRecord, fromViewController: fromViewController, forceDarkMode: forceDarkMode)
    }

    init(thread: TSThread, fromViewController: UIViewController, forceDarkMode: Bool = false) {
        self.thread = thread
        owsAssertDebug(thread is TSGroupThread)
        self.fromViewController = fromViewController
        self.forceDarkMode = forceDarkMode

        super.init(frame: .zero)

        createDefaultContents()
    }

    private func createDefaultContents() {
        // We want the background to extend to the bottom of the screen
        // behind the safe area, so we add that inset to our bottom inset
        // instead of pinning this view to the safe area
        let safeAreaInset = safeAreaInsets.bottom

        autoresizingMask = .flexibleHeight

        axis = .vertical
        spacing = 11
        layoutMargins = UIEdgeInsets(top: 16, leading: 16, bottom: 20 + safeAreaInset, trailing: 16)
        isLayoutMarginsRelativeArrangement = true
        alignment = .fill

        let blurView = UIVisualEffectView(effect: forceDarkMode ? Theme.darkThemeBarBlurEffect : Theme.barBlurEffect)
        addSubview(blurView)
        blurView.autoPinEdgesToSuperviewEdges()

        let format = OWSLocalizedString("GROUPS_ANNOUNCEMENT_ONLY_BLOCKING_SEND_OR_CALL_FORMAT",
                                       comment: "Format for indicator that only group administrators can starts a group call and sends messages to an 'announcement-only' group. Embeds {{ a \"admins\" link. }}.")
        let adminsText = OWSLocalizedString("GROUPS_ANNOUNCEMENT_ONLY_ADMINISTRATORS",
                                           comment: "Label for group administrators in the 'announcement-only' group UI.")
        let text = String(format: format, adminsText)
        let attributedString = NSMutableAttributedString(string: text)
        attributedString.setAttributes([
            .foregroundColor: forceDarkMode ? .ows_accentBlueDark : Theme.accentBlueColor
        ],
        forSubstring: adminsText)

        let label = UILabel()
        label.font = .dynamicTypeSubheadlineClamped
        label.textColor = forceDarkMode ? Theme.darkThemeSecondaryTextAndIconColor : Theme.secondaryTextAndIconColor
        label.attributedText = attributedString
        label.textAlignment = .center
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.isUserInteractionEnabled = true
        label.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTapContactAdmins)))
        addArrangedSubview(label)

        let lineView = UIView()
        lineView.backgroundColor = forceDarkMode ? .ows_gray75 : Theme.hairlineColor
        addSubview(lineView)
        lineView.autoSetDimension(.height, toSize: 1)
        lineView.autoPinWidthToSuperview()
        lineView.autoPinEdge(toSuperviewEdge: .top)
    }

    private func fetchGroupAdminAddresses(tx: DBReadTransaction) -> [SignalServiceAddress] {
        guard
            let groupThread = thread as? TSGroupThread,
            let groupModel = groupThread.groupModel as? TSGroupModelV2
        else {
            owsFailDebug("Invalid group.")
            return []
        }
        owsAssertDebug(groupModel.isAnnouncementsOnly)
        let groupAdminAddresses = Array(groupModel.groupMembership.fullMemberAdministrators)
        let contactManager = SSKEnvironment.shared.contactManagerRef
        return contactManager.sortSignalServiceAddresses(groupAdminAddresses, transaction: tx)

    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        return .zero
    }

    // MARK: -

    @objc
    public func didTapContactAdmins() {
        guard let fromViewController = fromViewController else {
            owsFailDebug("Missing fromViewController.")
            return
        }

        let databaseStorage = SSKEnvironment.shared.databaseStorageRef
        let groupAdmins = databaseStorage.read { tx in
            return self.fetchGroupAdminAddresses(tx: tx)
        }
        guard !groupAdmins.isEmpty else {
            owsFailDebug("No group admins.")
            return
        }

        let sheet = MessageUserSubsetSheet(addresses: groupAdmins, forceDarkMode: forceDarkMode)
        fromViewController.present(sheet, animated: true)
    }
}

// MARK: -

class MessageUserSubsetSheet: OWSTableSheetViewController {
    private let addresses: [SignalServiceAddress]
    private let forceDarkMode: Bool

    init(addresses: [SignalServiceAddress], forceDarkMode: Bool) {
        owsAssertDebug(!addresses.isEmpty)
        self.addresses = addresses
        self.forceDarkMode = forceDarkMode

        super.init()

        tableViewController.forceDarkMode = forceDarkMode

        tableViewController.defaultSeparatorInsetLeading = (OWSTableViewController2.cellHInnerMargin +
                                                            CGFloat(AvatarBuilder.smallAvatarSizePoints) +
                                                            ContactCellView.avatarTextHSpacing)

        tableViewController.tableView.register(
            ContactTableViewCell.self,
            forCellReuseIdentifier: ContactTableViewCell.reuseIdentifier)

        updateViewState()
    }

    // MARK: -

    public override func updateTableContents(shouldReload: Bool = true) {
        let contents = OWSTableContents()
        defer { tableViewController.setContents(contents, shouldReload: shouldReload) }

        let section = OWSTableSection()
        let header = OWSLocalizedString("GROUPS_ANNOUNCEMENT_ONLY_CONTACT_ADMIN",
                                       comment: "Label indicating the user can contact a group administrators of an 'announcement-only' group.")
        section.headerAttributedTitle = NSAttributedString(string: header, attributes: [
            .font: UIFont.dynamicTypeBodyClamped.semibold(),
            .foregroundColor: forceDarkMode ? Theme.darkThemePrimaryColor : Theme.primaryTextColor
            ])
        contents.add(section)
        for address in addresses {
            section.add(OWSTableItem(
                            dequeueCellBlock: { [weak self] tableView in
                                guard let cell = tableView.dequeueReusableCell(withIdentifier: ContactTableViewCell.reuseIdentifier) as? ContactTableViewCell else {
                                    owsFailDebug("Missing cell.")
                                    return UITableViewCell()
                                }

                                cell.selectionStyle = .none

                                let configuration = ContactCellConfiguration(address: address, localUserDisplayMode: .asLocalUser)
                                configuration.forceDarkAppearance = self?.forceDarkMode ?? false

                                SSKEnvironment.shared.databaseStorageRef.read {
                                    cell.configure(configuration: configuration, transaction: $0)
                                }

                                return cell
                            },
                actionBlock: { [weak self] in
                    self?.dismiss(animated: true) {
                        SignalApp.shared.presentConversationForAddress(address, action: .compose, animated: true)
                    }
                }))
        }
    }
}
