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

        let blurView = UIVisualEffectView(effect: Theme.barBlurEffect)
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
    override var interactiveScrollViews: [UIScrollView] { [tableViewController.tableView] }
    private let tableViewController = OWSTableViewController2()
    private let addresses: [SignalServiceAddress]
    override var renderExternalHandle: Bool { false }
    private let handleContainer = UIView()

    var contentSizeHeight: CGFloat {
        tableViewController.tableView.contentSize.height + tableViewController.tableView.adjustedContentInset.totalHeight
    }
    override var minimizedHeight: CGFloat {
        return min(contentSizeHeight, maximizedHeight)
    }
    override var maximizedHeight: CGFloat {
        min(contentSizeHeight, CurrentAppContext().frame.height - (view.safeAreaInsets.top + 32))
    }

    init(addresses: [SignalServiceAddress]) {
        owsAssertDebug(!addresses.isEmpty)
        self.addresses = addresses.stableSort()

        super.init()

        createContent()
    }

    public required init() {
        fatalError("init() has not been implemented")
    }

    // MARK: -

    override public func viewDidLoad() {
        super.viewDidLoad()

        updateTableContents()
    }

    override func themeDidChange() {
        super.themeDidChange()
        handleContainer.backgroundColor = tableViewController.tableBackgroundColor
        updateTableContents()
    }

    private func createContent() {
        addChild(tableViewController)
        let tableView = tableViewController.tableView
        tableViewController.shouldDeferInitialLoad = false
        tableViewController.defaultSeparatorInsetLeading = OWSTableViewController2.cellHInnerMargin + 24 + OWSTableItem.iconSpacing
        tableView.register(ContactTableViewCell.self,
                           forCellReuseIdentifier: ContactTableViewCell.reuseIdentifier)
        contentView.addSubview(tableViewController.view)
        tableViewController.view.autoPinEdgesToSuperviewEdges()

        // We add the handle directly to the content view,
        // so that it doesn't scroll with the table.
        handleContainer.backgroundColor = tableViewController.tableBackgroundColor
        contentView.addSubview(handleContainer)
        handleContainer.autoPinWidthToSuperview()
        handleContainer.autoPinEdge(toSuperviewEdge: .top)

        let handle = UIView()
        handle.backgroundColor = tableViewController.separatorColor
        handle.autoSetDimensions(to: CGSize(width: 36, height: 5))
        handle.layer.cornerRadius = 5 / 2
        handleContainer.addSubview(handle)
        handle.autoPinHeightToSuperview(withMargin: 12)
        handle.autoHCenterInSuperview()

        updateViewState()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        updateViewState()
    }

    private var previousMinimizedHeight: CGFloat?
    private var previousSafeAreaInsets: UIEdgeInsets?
    private func updateViewState() {
        if previousSafeAreaInsets != tableViewController.view.safeAreaInsets {
            updateTableContents()
            previousSafeAreaInsets = tableViewController.view.safeAreaInsets
        }
        if minimizedHeight != previousMinimizedHeight {
            heightConstraint?.constant = minimizedHeight
            previousMinimizedHeight = minimizedHeight
        }
    }

    private func updateTableContents() {
        let contents = OWSTableContents()

        // Leave space at the top for the handle
        let handleSection = OWSTableSection()
        handleSection.customHeaderHeight = 25
        contents.addSection(handleSection)

        let section = OWSTableSection()
        let header = NSLocalizedString("GROUPS_ANNOUNCEMENT_ONLY_CONTACT_ADMIN",
                                       comment: "Label indicating the user can contact a group administrators of an 'announcement-only' group.")
        section.headerAttributedTitle = NSAttributedString(string: header, attributes: [
            .font: UIFont.ows_dynamicTypeBodyClamped.ows_semibold,
            .foregroundColor: Theme.primaryTextColor
            ])
        contents.addSection(section)
        for address in addresses {
            section.add(OWSTableItem(
                            dequeueCellBlock: { tableView in
                                guard let cell = tableView.dequeueReusableCell(withIdentifier: ContactTableViewCell.reuseIdentifier) as? ContactTableViewCell else {
                                    owsFailDebug("Missing cell.")
                                    return UITableViewCell()
                                }

                                cell.selectionStyle = .none

                                cell.configureWithSneakyTransaction(address: address,
                                                                    localUserDisplayMode: .asLocalUser)

                                return cell
                            },
                actionBlock: { [weak self] in
                    self?.dismiss(animated: true) {
                        Self.signalApp.presentConversation(for: address,
                                                           action: .compose,
                                                           animated: true)
                    }
                }))
        }
        tableViewController.contents = contents
    }
}
