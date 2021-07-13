//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import UIKit
import PromiseKit

@objc
class BlockingAnnouncementOnlyView: UIStackView {

    private let thread: TSThread

    private weak var fromViewController: UIViewController?

    init(threadViewModel: ThreadViewModel, fromViewController: UIViewController) {
        let thread = threadViewModel.threadRecord
        self.thread = thread
        owsAssertDebug(thread as? TSGroupThread != nil)
        self.fromViewController = fromViewController

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

        let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .light))
        addSubview(blurView)
        blurView.autoPinEdgesToSuperviewEdges()

        let format = NSLocalizedString("GROUPS_ANNOUNCEMENT_ONLY_BLOCKING_SEND_OR_CALL_FORMAT",
                                       comment: "Format for indicator that only group administrators can starts a group call and sends messages to an 'announcement-only' group. Embeds {{ a \"admins\" link. }}.")
        let adminsText = NSLocalizedString("GROUPS_ANNOUNCEMENT_ONLY_ADMINISTRATORS",
                                           comment: "Label for group administrators in the 'announcement-only' group UI.")
        let text = String(format: format, adminsText)
        let attributedString = NSMutableAttributedString(string: text)
        attributedString.setAttributes([
            .foregroundColor: Theme.accentBlueColor
        ],
        forSubstring: adminsText)

        let label = UILabel()
        label.font = .ows_dynamicTypeSubheadlineClamped
        label.textColor = Theme.secondaryTextAndIconColor
        label.attributedText = attributedString
        label.textAlignment = .center
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.isUserInteractionEnabled = true
        label.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTapContactAdmins)))
        addArrangedSubview(label)

        let lineView = UIView()
        lineView.backgroundColor = Theme.hairlineColor
        addSubview(lineView)
        lineView.autoSetDimension(.height, toSize: 1)
        lineView.autoPinWidthToSuperview()
        lineView.autoPinEdge(toSuperviewEdge: .top)
    }

    private func groupAdmins() -> [SignalServiceAddress] {
        guard let groupThread = thread as? TSGroupThread,
              let groupModel = groupThread.groupModel as? TSGroupModelV2 else {
            owsFailDebug("Invalid group.")
            return []
        }
        owsAssertDebug(groupModel.isAnnouncementsOnly)
        return Array(groupModel.groupMembership.fullMemberAdministrators)

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

        let groupAdmins = self.groupAdmins()
        guard !groupAdmins.isEmpty else {
            owsFailDebug("No group admins.")
            return
        }

        let sheet = MessageUserSubsetSheet(addresses: groupAdmins)
        fromViewController.present(sheet, animated: true)
    }
}

// MARK: -

@objc
class MessageUserSubsetSheet: InteractiveSheetViewController {
    override var interactiveScrollViews: [UIScrollView] { [tableView] }
    private let tableView = UITableView(frame: .zero, style: .grouped)
    private let addresses: [SignalServiceAddress]

    init(addresses: [SignalServiceAddress]) {
        owsAssertDebug(!addresses.isEmpty)
        self.addresses = addresses.stableSort()
        super.init()
    }

    public required init() {
        fatalError("init() has not been implemented")
    }

    // MARK: -

    override public func viewDidLoad() {
        super.viewDidLoad()

//        if UIAccessibility.isReduceTransparencyEnabled {
//            contentView.backgroundColor = .ows_blackAlpha80
//        } else {
//            let blurEffectView = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
//            contentView.addSubview(blurEffectView)
//            blurEffectView.autoPinEdgesToSuperviewEdges()
//            contentView.backgroundColor = .ows_blackAlpha40
//        }

        tableView.dataSource = self
        tableView.delegate = self
//        tableView.backgroundColor = .clear
        tableView.backgroundColor = OWSTableViewController2.tableBackgroundColor(useNewStyle: true,
                                                                                 isUsingPresentedStyle: true,
                                                                                 useThemeBackgroundColors: false)

        tableView.separatorStyle = .none
        tableView.tableHeaderView = UIView(frame: CGRect(origin: .zero, size: CGSize(width: 0, height: CGFloat.leastNormalMagnitude)))
        contentView.addSubview(tableView)
        tableView.autoPinEdgesToSuperviewEdges()

        tableView.register(ContactTableViewCell.self,
                           forCellReuseIdentifier: ContactTableViewCell.reuseIdentifier)

        tableView.reloadData()
//        updateMembers()
    }
}

// MARK: -

extension MessageUserSubsetSheet: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        addresses.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: ContactTableViewCell.reuseIdentifier,
                                                       for: indexPath) as? ContactTableViewCell else {
            owsFailDebug("unexpected cell type")
            return UITableViewCell()
        }

        guard let address = addresses[safe: indexPath.row] else {
            owsFailDebug("missing address")
            return cell
        }

        cell.configureWithSneakyTransaction(address: address, localUserDisplayMode: .asLocalUser)

        return cell
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let label = UILabel()
        label.text = NSLocalizedString("GROUPS_ANNOUNCEMENT_ONLY_CONTACT_ADMIN",
                                       comment: "Label indicating the user can contact a group administrators of an 'announcement-only' group.")
        label.font = UIFont.ows_dynamicTypeBodyClamped.ows_semibold
        label.textColor = Theme.primaryTextColor
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping

        let labelContainer = UIView()
        labelContainer.layoutMargins = UIEdgeInsets(top: 13, left: 16, bottom: 13, right: 16)
        labelContainer.addSubview(label)
        label.autoPinEdgesToSuperviewMargins()
        return labelContainer
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return UITableView.automaticDimension
    }

    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        return .leastNormalMagnitude
    }

    open func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        Logger.verbose("")

        guard let address = addresses[safe: indexPath.row] else {
            owsFailDebug("missing address")
            return
        }

//
//        let cell = tableView.cellForRow(at: indexPath) as! ContactCell
//        let selectedContact = cell.contact!
//
//        guard contactsPickerDelegate == nil || contactsPickerDelegate!.contactsPicker(self, shouldSelectContact: selectedContact) else {
//            self.tableView.deselectRow(at: indexPath, animated: false)
//            return
//        }
//
//        selectedContacts.append(selectedContact)
//
//        if !allowsMultipleSelection {
//            // Single selection code
//            self.contactsPickerDelegate?.contactsPicker(self, didSelectContact: selectedContact)
//        }
    }
}
