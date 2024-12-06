//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalRingRTC
import SignalServiceKit
import SignalUI
import Combine

protocol CallDrawerDelegate: AnyObject {
    func didPresentViewController(_ viewController: UIViewController)
    func didTapDone()
}

// MARK: - GroupCallSheet

class CallDrawerSheet: InteractiveSheetViewController {
    private let callControls: CallControls

    // MARK: Properties

    override var interactiveScrollViews: [UIScrollView] { [tableView] }
    override var canBeDismissed: Bool {
        return false
    }
    override var canInteractWithParent: Bool {
        return true
    }

    private lazy var tableViewContainer: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = HeightConstants.titleViewBottomPadding
        stackView.addArrangedSubview(self.tableHeaderContainer)
        stackView.addArrangedSubview(self.tableView)
        return stackView
    }()
    private lazy var tableHeaderContainer: UIView = {
        let container = UIView()
        container.layoutMargins = .init(hMargin: 21, vMargin: 0)
        container.addSubview(self.sheetTitleLabel)
        self.sheetTitleLabel.autoHCenterInSuperview()
        self.sheetTitleLabel.autoPinHeightToSuperviewMargins()

        let doneButton = UIButton(primaryAction: .init(
            title: CommonStrings.doneButton
        ) { [weak self] _ in
            self?.callDrawerDelegate?.didTapDone()
        })
        container.addSubview(doneButton)
        doneButton.setTitleColor(UIColor.Signal.label, for: .normal)
        doneButton.titleLabel?.font = .dynamicTypeBody
        doneButton.autoAlignAxis(.horizontal, toSameAxisOf: self.sheetTitleLabel)
        doneButton.autoPinEdge(toSuperviewMargin: .trailing)
        doneButton.autoPinEdge(.leading, to: .trailing, of: sheetTitleLabel, withOffset: 8, relation: .greaterThanOrEqual)

        return container
    }()
    private let sheetTitleLabel: UILabel = {
        let label = UILabel()
        // "Call Info" for normal group calls. Will be
        // overwritten by call link state otherwise.
        label.text = OWSLocalizedString(
            "GROUP_CALL_MEMBER_LIST_TITLE",
            comment: "Title for the sheet showing the group call members list"
        )
        label.font = .dynamicTypeHeadline
        label.textColor = UIColor.Signal.label
        return label
    }()
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let call: SignalCall
    private let callSheetDataSource: CallDrawerSheetDataSource

    private weak var callDrawerDelegate: CallDrawerDelegate?

    private var callLinkDataSource: CallLinkSheetDataSource? {
        self.callSheetDataSource as? CallLinkSheetDataSource
    }

    private lazy var callLinkAdminManager: CallLinkAdminManager? = {
        guard
            let callLinkDataSource,
            let adminPasskey = callLinkDataSource.adminPasskey
        else { return nil }
        return CallLinkAdminManager(
            rootKey: callLinkDataSource.callLink.rootKey,
            adminPasskey: adminPasskey,
            callLinkState: callLinkDataSource.callLinkState
        )
    }()

    private var callLinkStateSubscription: AnyCancellable?

    private var didPresentViewController: ((UIViewController) -> Void)?

    override var sheetBackgroundColor: UIColor { UIColor(rgbHex: 0x1C1C1E) }

    override var handleBackgroundColor: UIColor { UIColor(rgbHex: 0x787880).withAlphaComponent(0.36) }

    init(
        call: SignalCall,
        callSheetDataSource: CallDrawerSheetDataSource,
        callService: CallService,
        confirmationToastManager: CallControlsConfirmationToastManager,
        callControlsDelegate: CallControlsDelegate,
        sheetPanDelegate: (any SheetPanDelegate)?,
        callDrawerDelegate: CallDrawerDelegate? = nil
    ) {
        self.call = call
        self.callSheetDataSource = callSheetDataSource
        self.callControls = CallControls(
            call: call,
            callService: callService,
            confirmationToastManager: confirmationToastManager,
            delegate: callControlsDelegate
        )

        super.init(blurEffect: nil)

        self.animationsShouldBeInterruptible = true
        self.sheetPanDelegate = sheetPanDelegate
        self.callDrawerDelegate = callDrawerDelegate

        self.overrideUserInterfaceStyle = .dark
        callSheetDataSource.addObserver(self, syncStateImmediately: true)
        callControls.addHeightObserver(self)
        self.tableViewContainer.alpha = 0
        // Don't add a dim visual effect to the call when the sheet is open.
        self.backdropColor = .clear
    }

    override func maximumPreferredHeight() -> CGFloat {
        guard let windowHeight = view.window?.frame.height else {
            return super.maximumPreferredHeight()
        }
        let halfHeight = windowHeight / 2
        let twoThirdsHeight = 2 * windowHeight / 3
        let tableHeight = tableView.contentSize.height
        + tableView.safeAreaInsets.totalHeight
        + Constants.handleHeight
        + tableHeaderContainer.frame.height
        + HeightConstants.titleViewBottomPadding
        + HeightConstants.tableViewTopPadding
        if tableHeight >= twoThirdsHeight {
            return twoThirdsHeight
        } else if tableHeight > halfHeight {
            return tableHeight
        } else {
            return halfHeight
        }
    }

    override func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)? = nil) {
        super.present(viewControllerToPresent, animated: flag, completion: completion)
        self.callDrawerDelegate?.didPresentViewController(viewControllerToPresent)
    }

    // MARK: - Table setup

    private typealias DiffableDataSource = UITableViewDiffableDataSource<Section, RowID>
    private typealias Snapshot = NSDiffableDataSourceSnapshot<Section, RowID>

    private enum Section: Hashable {
        case callLink
        case members(MembersSection)
        case admin
    }

    private enum MembersSection: Hashable {
        case raisedHands
        case inCall
    }

    private enum RowID: Hashable {
        case callLink(CallLinkRow)
        case member(section: MembersSection, id: JoinedMember.ID)
        case unknownMembers

        enum CallLinkRow: Hashable {
            case share
            case editName
        }
    }

    private lazy var dataSource = DiffableDataSource(
        tableView: tableView
    ) { [weak self] tableView, indexPath, id -> UITableViewCell? in
        switch id {
        case let .member(section: section, id: memberID):
            let cell = tableView.dequeueReusableCell(GroupCallMemberCell.self, for: indexPath)

            cell.delegate = self

            guard let viewModel = self?.viewModelsByID[memberID] else {
                owsFailDebug("missing view model")
                cell.hideContent()
                return cell
            }

            let isCallAdmin = self?.callLinkDataSource?.isAdmin ?? false
            let canBeRemoved = section == .inCall && !viewModel.isLocalUser && isCallAdmin

            let removeUserButtonVisibility: GroupCallMemberCell.Visibility =
            if canBeRemoved {
                .visible
            } else if isCallAdmin && section == .inCall {
                .spaceReserved
            } else {
                .hidden
            }

            cell.configure(
                with: viewModel,
                isHandRaised: section == .raisedHands,
                removeUserButtonVisibility: removeUserButtonVisibility
            )

            return cell
        case .callLink(.share):
            return tableView.dequeueReusableCell(CallLinkURLCell.self, for: indexPath)
        case .callLink(.editName):
            let cell = tableView.dequeueReusableCell(withIdentifier: "UITableViewCell", for: indexPath)
            var config = cell.defaultContentConfiguration()
            config.text = self?.callLinkAdminManager?.editCallNameButtonTitle
            cell.contentConfiguration = config
            cell.accessoryType = .disclosureIndicator
            cell.contentView.layoutMargins.top = 14
            cell.contentView.layoutMargins.bottom = 14
            return cell
        case .unknownMembers:
            let cell = tableView.dequeueReusableCell(UnknownMembersCell.self, for: indexPath)
            if let self {
                cell.parentViewController = self
                cell.unknownMembers = self.unknownMembers
            }
            return cell
        }
    }

    private class HeaderView: UIView {
        private let section: MembersSection
        var memberCount: Int = 0 {
            didSet {
                self.updateText()
            }
        }

        private let label = UILabel()

        init(section: MembersSection) {
            self.section = section
            super.init(frame: .zero)

            self.addSubview(self.label)
            self.label.autoPinEdgesToSuperviewMargins()
            self.updateText()
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        private func updateText() {
            let titleText: String = switch section {
            case .raisedHands:
                OWSLocalizedString(
                    "GROUP_CALL_MEMBER_LIST_RAISED_HANDS_SECTION_HEADER",
                    comment: "Title for the section of the group call member list which displays the list of members with their hand raised."
                )
            case .inCall:
                OWSLocalizedString(
                    "GROUP_CALL_MEMBER_LIST_IN_CALL_SECTION_HEADER",
                    comment: "Title for the section of the group call member list which displays the list of all members in the call."
                )
            }

            label.attributedText = .composed(of: [
                titleText.styled(with: .font(.dynamicTypeHeadline)),
                " ",
                String(
                    format: OWSLocalizedString(
                        "GROUP_CALL_MEMBER_LIST_SECTION_HEADER_MEMBER_COUNT",
                        comment: "A count of members in a given group call member list section, displayed after the header."
                    ),
                    self.memberCount
                )
            ]).styled(
                with: .font(.dynamicTypeBody),
                .color(Theme.darkThemePrimaryColor)
            )
        }
    }

    private let raisedHandsHeader = HeaderView(section: .raisedHands)
    private let inCallHeader = HeaderView(section: .inCall)

    func setBottomSheetMinimizedHeight() {
        minimizedHeight = callControls.currentHeight + self.bottomPadding
    }

    private func setTableViewTopTranslation(to translation: CGFloat) {
        tableViewContainer.transform = .translate(.init(x: 0, y: translation))
    }

    override public func viewDidLoad() {
        super.viewDidLoad()

        tableView.delegate = self
        tableView.tableHeaderView = UIView(frame: CGRect(origin: .zero, size: CGSize(width: 0, height: CGFloat.leastNormalMagnitude)))
        tableView.backgroundColor = sheetBackgroundColor
        contentView.addSubview(tableViewContainer)
        tableViewContainer.autoPinEdgesToSuperviewEdges()

        if let callLinkAdminManager {
            callLinkStateSubscription = callLinkAdminManager.callNamePublisher
                .removeDuplicates()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] callLinkName in
                    self?.callLinkNameDidChange(callLinkName)
                }
        }

        tableView.register(CallLinkURLCell.self)
        tableView.register(GroupCallMemberCell.self)
        tableView.register(UnknownMembersCell.self)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "UITableViewCell")

        tableView.dataSource = self.dataSource

        callControls.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(callControls)
        NSLayoutConstraint.activate([
            callControls.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            callControls.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10)
        ])

        updateMembers()
    }

    // MARK: - Table contents

    struct JoinedMember {
        enum ID: Hashable {
            case aci(Aci)
            case demuxID(DemuxId)
        }

        let id: ID

        let aci: Aci
        let displayName: String
        let comparableName: DisplayName.ComparableValue
        let demuxID: DemuxId?
        let isLocalUser: Bool
        let isUnknown: Bool
        let isAudioMuted: Bool?
        let isVideoMuted: Bool?
        let isPresenting: Bool?
    }

    fileprivate struct UnknownMembers {
        var members: [JoinedMember]
        var count: Int { members.count }
        var callHasKnownUsers: Bool

        init() {
            self.members = []
            self.callHasKnownUsers = false
        }
    }

    private var unknownMembers = UnknownMembers()
    private var viewModelsByID: [JoinedMember.ID: GroupCallMemberCell.ViewModel] = [:]
    private var sortedMembers = [JoinedMember]() {
        didSet {
            let oldMemberIDs = viewModelsByID.keys
            let newMemberIDs = sortedMembers.map(\.id)
            let viewModelsToRemove = Set(oldMemberIDs).subtracting(newMemberIDs)
            if !viewModelsToRemove.isEmpty {
                Logger.info("Removing \(viewModelsToRemove.count) view models")
            }
            viewModelsToRemove.forEach { viewModelsByID.removeValue(forKey: $0) }

            viewModelsByID = sortedMembers.reduce(into: viewModelsByID) { partialResult, member in
                if let existingViewModel = partialResult[member.id] {
                    existingViewModel.update(using: member)
                } else {
                    partialResult[member.id] = .init(member: member)
                }
            }
        }
    }

    func updateMembers() {
        Logger.info("")
        let unsortedMembers: [JoinedMember] = SSKEnvironment.shared.databaseStorageRef.read {
            callSheetDataSource.unsortedMembers(tx: $0.asV2Read)
        }

        typealias OrganizedMembers = (joinedMembers: [JoinedMember], unknownMembers: UnknownMembers)

        let organizedMembers: OrganizedMembers = unsortedMembers.reduce(
            into: ([], UnknownMembers())
        ) { partialResult, member in
            if member.isUnknown {
                partialResult.unknownMembers.members.append(member)
            } else {
                partialResult.joinedMembers.append(member)
                partialResult.unknownMembers.callHasKnownUsers = true
            }
        }

        self.sortedMembers = organizedMembers.joinedMembers.sorted {
            let nameComparison = $0.comparableName.isLessThanOrNilIfEqual($1.comparableName)
            if let nameComparison {
                return nameComparison
            }
            if $0.aci != $1.aci {
                return $0.aci < $1.aci
            }
            return $0.demuxID ?? 0 < $1.demuxID ?? 0
        }

        self.unknownMembers = organizedMembers.unknownMembers

        self.updateSnapshotAndHeaders()
    }

    private var previousSnapshotItems: [RowID]?

    @MainActor
    private func updateSnapshotAndHeaders() {
        AssertIsOnMainThread()
        var snapshot = Snapshot()

        let isCallAdmin = callLinkDataSource?.isAdmin ?? false

        // Call link info
        if callLinkDataSource != nil {
            snapshot.appendSections([.callLink])
            snapshot.appendItems([.callLink(.share)], toSection: .callLink)
        }

        // Raised hands
        let raiseHandMemberIds = callSheetDataSource.raisedHandMemberIds()
        if !raiseHandMemberIds.isEmpty {
            snapshot.appendSections([.members(.raisedHands)])
            snapshot.appendItems(
                raiseHandMemberIds.map {
                    RowID.member(section: .raisedHands, id: $0)
                },
                toSection: .members(.raisedHands)
            )

            raisedHandsHeader.memberCount = raiseHandMemberIds.count
        }

        // Call members
        let shouldHideMembersSection = isCallAdmin && sortedMembers.isEmpty && unknownMembers.count == 0
        if !shouldHideMembersSection {
            snapshot.appendSections([.members(.inCall)])
            snapshot.appendItems(
                sortedMembers.map { RowID.member(section: .inCall, id: $0.id) },
                toSection: .members(.inCall)
            )

            if unknownMembers.count > 0 {
                snapshot.appendItems([.unknownMembers], toSection: .members(.inCall))
            }
        }

        inCallHeader.memberCount = sortedMembers.count + unknownMembers.count

        // Call link admin
        if isCallAdmin {
            snapshot.appendSections([.admin])
            snapshot.appendItems([
                .callLink(.editName),
            ])
        }

        // Apply snapshot
        Logger.info("Applying snapshot")
        if self.previousSnapshotItems != snapshot.itemIdentifiers {
            self.previousSnapshotItems = snapshot.itemIdentifiers
            dataSource.apply(snapshot, animatingDifferences: true) { [weak self] in
                Logger.info("Snapshot applied")
                self?.refreshMaxHeight()
            }
        }
    }

    private func callLinkNameDidChange(_ callLinkName: String?) {
        sheetTitleLabel.text = callLinkName ?? SignalServiceKit.CallLinkState.defaultLocalizedName
        var snapshot = dataSource.snapshot()
        snapshot.reloadSections([.admin])
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    private func changesForSnapToMax() {
        self.tableViewContainer.alpha = 1
        self.callControls.alpha = 0
        self.setTableViewTopTranslation(to: 0)
        self.view.layoutIfNeeded()
    }

    private func changesForSnapToMin() {
        self.tableViewContainer.alpha = 0
        self.callControls.alpha = 1
        self.setTableViewTopTranslation(to: HeightConstants.initialTableInset)
        self.view.layoutIfNeeded()
    }

    /// The portion of the height of the sheet to pivot the fade transition over
    private let pivot: CGFloat = 0.2
    private var lastKnownHeight: SheetHeight = .min

    override func heightDidChange(to height: InteractiveSheetViewController.SheetHeight) {
        switch height {
        case .min:
            guard UIView.inheritedAnimationDuration > 0 else {
                changesForSnapToMin()
                break
            }

            let currentHeight = switch lastKnownHeight {
            case .min:
                self.minimizedHeight
            case .max:
                self.maxHeight
            case .height(let height):
                height
            }

            let currentHeightProportional = (currentHeight - self.minimizedHeight) / (self.maxHeight - self.minimizedHeight)

            let tableFadePortion = max((currentHeightProportional - self.pivot) / currentHeightProportional, 0)
            let controlsFadePortion = 1 - tableFadePortion

            // Inherit the animation
            UIView.animateKeyframes(withDuration: 0, delay: 0) {
                UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: tableFadePortion) {
                    self.tableViewContainer.alpha = 0
                    self.setTableViewTopTranslation(to: HeightConstants.initialTableInset)
                }
                UIView.addKeyframe(withRelativeStartTime: tableFadePortion, relativeDuration: controlsFadePortion) {
                    self.callControls.alpha = 1
                }
            }
        case .height(let height):
            let distance = self.maxHeight - self.minimizedHeight

            // The "pivot point" is the sheet height where call controls have totally
            // faded out and the call info table begins to fade in.
            let pivotPoint = minimizedHeight + self.pivot * distance

            if height <= self.minimizedHeight {
                changesForSnapToMin()
            } else if height > self.minimizedHeight && height < pivotPoint {
                tableViewContainer.alpha = 0
                let denominator = pivotPoint - self.minimizedHeight
                if denominator <= 0 {
                    owsFailBeta("You've changed the conditions of this if-branch such that the denominator could be zero!")
                    callControls.alpha = 1
                } else {
                    callControls.alpha = max(0.1, 1 - ((height - self.minimizedHeight) / denominator))
                }
            } else if height >= pivotPoint && height < maxHeight {
                callControls.alpha = 0

                // Table view fades in as sheet opens and fades out as sheet closes.
                let denominator = maxHeight - pivotPoint
                if denominator <= 0 {
                    owsFailBeta("You've changed the conditions of this if-branch such that the denominator could be zero!")
                    tableViewContainer.alpha = 0
                } else {
                    tableViewContainer.alpha = max(0.1, (height - pivotPoint) / denominator)
                }

                // Table view slides up via a y-shift to its final position as the sheet opens.

                // The distance across which the y-shift will be completed.
                let totalTravelableDistanceForSheet = maxHeight - pivotPoint
                // The distance traveled in the y-shift range.
                let distanceTraveledBySheetSoFar = height - pivotPoint
                // Table travel distance per unit sheet travel distance.
                let stepSize = HeightConstants.initialTableInset / totalTravelableDistanceForSheet
                // How far the table should have traveled.
                let tableTravelDistance = stepSize * distanceTraveledBySheetSoFar
                self.setTableViewTopTranslation(to: HeightConstants.initialTableInset - tableTravelDistance)
            } else if height >= maxHeight {
                changesForSnapToMax()
            }
        case .max:
            guard UIView.inheritedAnimationDuration > 0 else {
                changesForSnapToMax()
                break
            }

            let currentHeight = switch lastKnownHeight {
            case .min:
                self.minimizedHeight
            case .max:
                self.maxHeight
            case .height(let height):
                height
            }

            // Basically the same as the .min case, but flipped upside-down
            //  - Height of 1 = bottom
            //  - Treat pivot as 1 - its value
            let currentHeightProportional = 1 - ((currentHeight - self.minimizedHeight) / (self.maxHeight - self.minimizedHeight))

            let controlsFadePortion = max((currentHeightProportional - (1 - self.pivot)) / currentHeightProportional, 0)
            let tableFadePortion = 1 - controlsFadePortion

            UIView.animateKeyframes(withDuration: 0, delay: 0) {
                UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: controlsFadePortion) {
                    self.callControls.alpha = 0
                }
                UIView.addKeyframe(withRelativeStartTime: controlsFadePortion, relativeDuration: tableFadePortion) {
                    self.tableViewContainer.alpha = 1
                    self.setTableViewTopTranslation(to: 0)
                }
            }
        }

        self.lastKnownHeight = height
    }

    override func themeDidChange() {
        // The call drawer always uses dark styling regardless of the
        // system setting, so ignore.
    }
}

// MARK: UITableViewDelegate

extension CallDrawerSheet: UITableViewDelegate {
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let section = dataSource.snapshot().sectionIdentifiers[section]
        switch section {
        case .callLink, .admin:
            return nil
        case .members(.raisedHands):
            return raisedHandsHeader
        case .members(.inCall):
            return inCallHeader
        }
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        let section = dataSource.snapshot().sectionIdentifiers[section]
        switch section {
        case .callLink:
            return HeightConstants.tableViewTopPadding
        case .members, .admin:
            return UITableView.automaticDimension
        }
    }

    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        return .leastNormalMagnitude
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let section = dataSource.snapshot().sectionIdentifiers[indexPath.section]
        let row = dataSource.snapshot().itemIdentifiers(inSection: section)[indexPath.row]
        switch row {
        case .callLink(.share):
            tableView.deselectRow(at: indexPath, animated: true)
            self.shareCallLink()
        case .callLink(.editName):
            tableView.deselectRow(at: indexPath, animated: true)
            self.editCallName()
        case .member, .unknownMembers:
            tableView.deselectRow(at: indexPath, animated: false)
        }
    }

    private func shareCallLink() {
        AssertIsOnMainThread()
        guard let callLinkDataSource else {
            owsFailDebug("Contains call link section without a call link data source")
            return
        }

        let shareSheet = UIActivityViewController(
            activityItems: [callLinkDataSource.url()],
            applicationActivities: nil
        )
        present(shareSheet, animated: true)
    }

    private func editCallName() {
        guard let callLinkAdminManager else {
            owsFailDebug("Contains call admin section without a call link admin manager")
            return
        }

        EditCallLinkNameViewController(
            oldName: callLinkAdminManager.callLinkState?.name ?? "",
            setNewName: { name in
                try await callLinkAdminManager.updateName(name)
            }
        ).presentInNavController(from: self, forceDarkMode: true)
    }
}

// MARK: GroupCallMemberCellDelegate

extension CallDrawerSheet: GroupCallMemberCellDelegate {
    func raiseHand(raise: Bool) {
        callSheetDataSource.raiseHand(raise: raise)
    }

    func removeMember(demuxId: DemuxId) {
        guard let callLinkDataSource else {
            return owsFailDebug("Missing call link data source")
        }
        guard let name = viewModelsByID[.demuxID(demuxId)]?.name else {
            return owsFailDebug("Missing view model for demux ID")
        }

        let actionSheet = ActionSheetController(
            title: String(
                format: OWSLocalizedString(
                    "GROUP_CALL_REMOVE_MEMBER_CONFIRMATION_ACTION_SHEET_TITLE",
                    comment: "Title for action sheet confirming removal of a member from a group call. embeds {{ name }}"
                ),
                name
            ),
            theme: .translucentDark
        )
        actionSheet.addAction(.init(
            title: OWSLocalizedString(
                "GROUP_CALL_REMOVE_MEMBER_CONFIRMATION_ACTION_SHEET_REMOVE_ACTION",
                comment: "Label for the button to confirm removing a member from a group call."
            )
        ) { [callLinkDataSource] _ in
            callLinkDataSource.removeMember(demuxId: demuxId)
        })
        actionSheet.addAction(.init(
            title: OWSLocalizedString(
                "GROUP_CALL_REMOVE_MEMBER_CONFIRMATION_ACTION_SHEET_BLOCK_ACTION",
                comment: "Label for a button to block a member from a group call."
            )
        ) { [callLinkDataSource] _ in
            callLinkDataSource.blockMember(demuxId: demuxId)
        })
        actionSheet.addAction(.cancel)

        self.presentActionSheet(actionSheet)
    }
}

// MARK: CallObserver

extension CallDrawerSheet: CallDrawerSheetDataSourceObserver {
    func callSheetMembershipDidChange(_ dataSource: CallDrawerSheetDataSource) {
        AssertIsOnMainThread()
        updateMembers()
    }

    func callSheetRaisedHandsDidChange(_ dataSource: CallDrawerSheetDataSource) {
        AssertIsOnMainThread()
        updateSnapshotAndHeaders()
    }
}

extension CallDrawerSheet: EmojiPickerSheetPresenter {
    func present(sheet: EmojiPickerSheet, animated: Bool) {
        self.present(sheet, animated: animated)
    }
}

extension CallDrawerSheet {
    func isPresentingCallControls() -> Bool {
        return self.presentingViewController != nil && callControls.alpha == 1
    }

    func isPresentingCallInfo() -> Bool {
        return self.presentingViewController != nil && tableViewContainer.alpha == 1
    }

    func isCrossFading() -> Bool {
        return self.presentingViewController != nil && callControls.alpha < 1 && tableView.alpha < 1
    }
}

// MARK: - CallLinkURLCell

private class CallLinkURLCell: UITableViewCell, ReusableTableViewCell {
    static var reuseIdentifier = "CallLinkURLCell"

    static let iconBackgroundSize: CGFloat = 36

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        let hStack = UIStackView()
        hStack.axis = .horizontal
        hStack.spacing = 12

        let iconBackground = UIView()
        hStack.addArrangedSubview(iconBackground)
        iconBackground.backgroundColor = .ows_gray60
        iconBackground.autoSetDimensions(to: .square(Self.iconBackgroundSize))
        iconBackground.layer.cornerRadius = Self.iconBackgroundSize / 2

        let icon = UIImageView(image: Theme.iconImage(.buttonLink))
        iconBackground.addSubview(icon)
        icon.tintColor = .white
        icon.autoCenterInSuperview()

        let titleLabel = UILabel()
        hStack.addArrangedSubview(titleLabel)
        titleLabel.font = .dynamicTypeBody
        titleLabel.textColor = .white
        titleLabel.text = OWSLocalizedString(
            "GROUP_CALL_MEMBER_LIST_SHARE_CALL_LINK_BUTTON",
            comment: "Title for a button on the group members sheet for sharing that call's link."
        )

        self.contentView.addSubview(hStack)
        hStack.autoPinWidthToSuperviewMargins()
        hStack.autoPinHeightToSuperview(withMargin: 7)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - GroupCallMemberCell

protocol GroupCallMemberCellDelegate: AnyObject {
    func raiseHand(raise: Bool)
    func removeMember(demuxId: DemuxId)
}

private class GroupCallMemberCell: UITableViewCell, ReusableTableViewCell {

    // MARK: ViewModel

    class ViewModel {
        typealias Member = CallDrawerSheet.JoinedMember

        let aci: Aci
        let name: String
        let isLocalUser: Bool
        let demuxId: DemuxId?

        @Published var shouldShowAudioMutedIcon = false
        @Published var shouldShowVideoMutedIcon = false
        @Published var shouldShowPresentingIcon = false

        init(member: Member) {
            self.aci = member.aci
            self.name = member.displayName
            self.isLocalUser = member.isLocalUser
            self.demuxId = member.demuxID
            self.update(using: member)
        }

        func update(using member: Member) {
            owsAssertDebug(aci == member.aci)
            self.shouldShowAudioMutedIcon = member.isAudioMuted ?? false
            self.shouldShowVideoMutedIcon = member.isVideoMuted == true && member.isPresenting != true
            self.shouldShowPresentingIcon = member.isPresenting ?? false
        }
    }

    // MARK: Properties

    static let reuseIdentifier = "GroupCallMemberCell"

    weak var delegate: GroupCallMemberCellDelegate?

    private let avatarView = ConversationAvatarView(
        sizeClass: .thirtySix,
        localUserDisplayMode: .asUser,
        badged: false
    )

    private let nameLabel = UILabel()

    private lazy var lowerHandButton = OWSButton(
        title: CallStrings.lowerHandButton,
        tintColor: .ows_white,
        dimsWhenHighlighted: true
    ) { [weak self] in
        self?.delegate?.raiseHand(raise: false)
    }

    private var demuxId: DemuxId?
    private lazy var removeUserButton: OWSButton = {
        let button = OWSButton { [weak self] in
            guard let self, let demuxId else { return }
            self.delegate?.removeMember(demuxId: demuxId)
        }
        button.setAttributedTitle(
            SignalSymbol.minusCircle.attributedString(
                dynamicTypeBaseSize: 24,
                weight: .light,
                attributes: [.foregroundColor: UIColor.Signal.label]
            ),
            for: .normal
        )
        button.dimsWhenHighlighted = true
        return button
    }()

    private let leadingWrapper = UIView()
    private let videoMutedIndicator = UIImageView()
    private let presentingIndicator = UIImageView()

    private let audioMutedIndicator = UIImageView()
    private let raisedHandIndicator = UIImageView()

    private var subscriptions = Set<AnyCancellable>()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        selectionStyle = .none

        nameLabel.textColor = Theme.darkThemePrimaryColor
        nameLabel.font = .dynamicTypeBody

        lowerHandButton.titleLabel?.font = .dynamicTypeBody

        func setup(iconView: UIImageView, withImageNamed imageName: String, in wrapper: UIView) {
            iconView.setTemplateImageName(imageName, tintColor: Theme.darkThemeSecondaryTextAndIconColor)
            wrapper.addSubview(iconView)
            iconView.autoPinEdgesToSuperviewEdges()
            iconView.setCompressionResistanceHorizontalHigh()
            iconView.setContentHuggingHorizontalHigh()
        }

        let trailingWrapper = UIView()
        setup(iconView: audioMutedIndicator, withImageNamed: "mic-slash", in: trailingWrapper)
        setup(iconView: raisedHandIndicator, withImageNamed: Theme.iconName(.raiseHand), in: trailingWrapper)

        setup(iconView: videoMutedIndicator, withImageNamed: "video-slash", in: leadingWrapper)
        setup(iconView: presentingIndicator, withImageNamed: "share_screen", in: leadingWrapper)

        let stackView = UIStackView(arrangedSubviews: [
            avatarView,
            nameLabel,
            lowerHandButton,
            leadingWrapper,
            trailingWrapper,
            removeUserButton,
        ])
        stackView.axis = .horizontal
        stackView.alignment = .center
        contentView.addSubview(stackView)
        stackView.autoPinWidthToSuperviewMargins()
        stackView.autoPinHeightToSuperview(withMargin: 7)

        stackView.spacing = 16
        stackView.setCustomSpacing(12, after: avatarView)
        stackView.setCustomSpacing(8, after: nameLabel)

        nameLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        nameLabel.setContentHuggingHorizontalLow()
        nameLabel.setCompressionResistanceHorizontalLow()
        [leadingWrapper, trailingWrapper, removeUserButton, lowerHandButton]
            .forEach {
                $0.setContentHuggingHorizontalHigh()
                $0.setCompressionResistanceHorizontalHigh()
            }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Configuration

    enum Visibility {
        case visible, spaceReserved, hidden
    }

    // isHandRaised isn't part of ViewModel because the same view model is used
    // for any given member in both the members and raised hand sections.
    func configure(
        with viewModel: ViewModel,
        isHandRaised: Bool,
        removeUserButtonVisibility: Visibility
    ) {
        self.subscriptions.removeAll()

        if isHandRaised {
            self.raisedHandIndicator.isHidden = false
            self.lowerHandButton.isHiddenInStackView = !viewModel.isLocalUser
            self.audioMutedIndicator.isHidden = true
            self.leadingWrapper.isHiddenInStackView = true
        } else {
            self.raisedHandIndicator.isHidden = true
            self.lowerHandButton.isHiddenInStackView = true
            self.leadingWrapper.isHiddenInStackView = false
            self.subscribe(to: viewModel.$shouldShowAudioMutedIcon, showing: self.audioMutedIndicator)
            self.subscribe(to: viewModel.$shouldShowVideoMutedIcon, showing: self.videoMutedIndicator)
            self.subscribe(to: viewModel.$shouldShowPresentingIcon, showing: self.presentingIndicator)
        }

        self.nameLabel.text = viewModel.name
        self.avatarView.updateWithSneakyTransactionIfNecessary { config in
            config.dataSource = .address(SignalServiceAddress(viewModel.aci))
        }

        self.demuxId = viewModel.demuxId
        switch removeUserButtonVisibility {
        case .visible:
            self.removeUserButton.isHiddenInStackView = false
            self.removeUserButton.layer.opacity = 1
        case .spaceReserved:
            self.removeUserButton.isHiddenInStackView = false
            self.removeUserButton.layer.opacity = 0
        case .hidden:
            self.removeUserButton.isHiddenInStackView = true
        }
    }

    func hideContent() {
        self.raisedHandIndicator.isHidden = true
        self.lowerHandButton.isHiddenInStackView = true
        self.audioMutedIndicator.isHidden = true
        self.leadingWrapper.isHiddenInStackView = true
        self.removeUserButton.isHiddenInStackView = true
    }

    private func subscribe(to publisher: Published<Bool>.Publisher, showing view: UIView) {
        publisher
            .removeDuplicates()
            .sink { [weak view] shouldShow in
                view?.isHidden = !shouldShow
            }
            .store(in: &self.subscriptions)
    }
}

// MARK: - UnknownMembersCell

private class UnknownMembersCell: UITableViewCell, ReusableTableViewCell {
    static let reuseIdentifier: String = "UnknownMembersCell"

    typealias UnknownMembers = CallDrawerSheet.UnknownMembers

    private enum Constants {
        static let borderWidth: CGFloat = 1.75
        static let singleAvatarSize: UInt = 36
        static let twoAvatarsSize: UInt = 31
        static let threeAvatarsSize: UInt = 27
    }

    weak var parentViewController: UIViewController?
    var unknownMembers = UnknownMembers() {
        didSet {
            updateContents()
        }
    }

    private let bodyLabel: UILabel = {
        let label = UILabel()
        label.font = .dynamicTypeBody
        label.textColor = UIColor.Signal.label
        return label
    }()

    private let avatarContainer = UIView()

    private let frontAvatar: Avatar
    private let middleAvatar: Avatar
    private let backAvatar: Avatar

    private struct Avatar {
        let avatarView = ConversationAvatarView(localUserDisplayMode: .asUser, badged: false)
        let borderView = CircleView()
        let borderConstraints: [NSLayoutConstraint]

        enum Position {
            case front, middle, back
        }

        init(in containerView: UIView, position: Position) {
            containerView.addSubview(borderView)
            borderView.backgroundColor = .secondarySystemGroupedBackground
            borderConstraints = borderView.autoSetDimensions(to: .square(Self.borderSize(for: Constants.singleAvatarSize)))

            containerView.addSubview(avatarView)
            avatarView.autoVCenterInSuperview()
            switch position {
            case .front:
                avatarView.autoPinEdge(toSuperviewEdge: .trailing)
                avatarView.autoPinEdge(toSuperviewEdge: .leading, relation: .greaterThanOrEqual)
            case .middle:
                avatarView.autoHCenterInSuperview()
            case .back:
                avatarView.autoPinEdge(toSuperviewEdge: .leading)
                avatarView.autoPinEdge(toSuperviewEdge: .trailing, relation: .greaterThanOrEqual)
            }

            avatarView.updateWithSneakyTransactionIfNecessary { configuration in
                configuration.sizeClass = .customDiameter(Constants.singleAvatarSize)
                configuration.dataSource = nil
            }

            borderView.autoAlignAxis(.horizontal, toSameAxisOf: avatarView)
            borderView.autoAlignAxis(.vertical, toSameAxisOf: avatarView)

            borderView.isHiddenInStackView = true
            avatarView.isHiddenInStackView = true
        }

        func configure(with aci: Aci?, totalAvatars: Int) {
            guard let aci else {
                borderView.isHiddenInStackView = true
                avatarView.isHiddenInStackView = true
                return
            }
            borderView.isHiddenInStackView = false
            avatarView.isHiddenInStackView = false
            avatarView.updateWithSneakyTransactionIfNecessary { configuration in
                configuration.dataSource = .address(SignalServiceAddress(aci))

                let avatarSize = Self.avatarSize(for: totalAvatars)
                configuration.sizeClass = .customDiameter(avatarSize)

                let borderSize = Self.borderSize(for: avatarSize)
                self.borderConstraints.forEach { $0.constant = borderSize }
            }
        }

        func hide() {
            borderView.isHiddenInStackView = true
            avatarView.isHiddenInStackView = true
        }

        private static func avatarSize(for totalAvatars: Int) -> UInt {
            if totalAvatars == 1 {
                Constants.singleAvatarSize
            } else if totalAvatars == 2 {
                Constants.twoAvatarsSize
            } else {
                Constants.threeAvatarsSize
            }
        }

        private static func borderSize(for avatarSize: UInt) -> CGFloat {
            CGFloat(avatarSize) + Constants.borderWidth * 2
        }
    }

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        backAvatar = Avatar(in: avatarContainer, position: .back)
        middleAvatar = Avatar(in: avatarContainer, position: .middle)
        frontAvatar = Avatar(in: avatarContainer, position: .front)

        super.init(style: style, reuseIdentifier: reuseIdentifier)

        let hStack = UIStackView()
        self.contentView.addSubview(hStack)
        hStack.autoPinWidthToSuperviewMargins()
        hStack.autoPinHeightToSuperview(withMargin: 7)
        hStack.axis = .horizontal
        hStack.spacing = 12

        hStack.addArrangedSubview(avatarContainer)
        avatarContainer.autoSetDimensions(to: .square(CGFloat(Constants.singleAvatarSize)))

        hStack.addArrangedSubview(bodyLabel)

        let infoButton = OWSButton(
            imageName: "info",
            tintColor: .white,
            dimsWhenHighlighted: true
        ) { [weak self] in
            let actionSheet = ActionSheetController(
                message: OWSLocalizedString(
                    "GROUP_CALL_MEMBER_LIST_UNKNOWN_MEMBERS_INFO_SHEET",
                    comment: "Message on an action sheet when tapping an info button next to unknown members in the group call member list."
                ),
                theme: .translucentDark
            )
            actionSheet.addAction(.acknowledge)
            self?.parentViewController?.presentActionSheet(actionSheet)
        }
        hStack.addArrangedSubview(infoButton)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func updateContents() {
        if unknownMembers.count == 1, !unknownMembers.callHasKnownUsers {
            bodyLabel.text = OWSLocalizedString(
                "GROUP_CALL_MEMBER_LIST_SINGLE_UNKNOWN_MEMBER_ROW",
                comment: "Label for an unknown member in the group call member list when they are the only member of the call."
            )
        } else {
            bodyLabel.text = String(
                format: OWSLocalizedString(
                    "GROUP_CALL_MEMBER_LIST_UNKNOWN_MEMBERS_ROW_%ld",
                    tableName: "PluralAware",
                    comment: "Label for one or more unknown members in the group call member list when there is at least one known member in the call. Embeds {{ count }}"
                ),
                unknownMembers.count
            )
        }

        frontAvatar.configure(
            with: unknownMembers.members.first?.aci,
            totalAvatars: unknownMembers.members.count
        )
        if unknownMembers.members.count == 2 {
            middleAvatar.hide()
            backAvatar.configure(
                with: unknownMembers.members.last?.aci,
                totalAvatars: unknownMembers.members.count
            )
        } else {
            middleAvatar.configure(
                with: unknownMembers.members[safe: 1]?.aci,
                totalAvatars: unknownMembers.members.count
            )
            backAvatar.configure(
                with: unknownMembers.members[safe: 2]?.aci,
                totalAvatars: unknownMembers.members.count
            )
        }
    }
}

// MARK: - CallControlsHeightObserver

extension CallDrawerSheet: CallControlsHeightObserver {
    func callControlsHeightDidChange(newHeight: CGFloat) {
        self.cancelAnimationAndUpdateConstraints()
        self.animate {
            self.setBottomSheetMinimizedHeight()
            self.view.layoutIfNeeded()
        }
    }

    open override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        self.setBottomSheetMinimizedHeight()
    }

    private var bottomPadding: CGFloat {
        max(self.view.safeAreaInsets.bottom + HeightConstants.bottomPadding, HeightConstants.minimumBottomPaddingIncludingSafeArea)
    }

    private enum HeightConstants {
        static let bottomPadding: CGFloat = 14
        static let minimumBottomPaddingIncludingSafeArea: CGFloat = 30
        static let initialTableInset: CGFloat = 25
        static let titleViewBottomPadding: CGFloat = 16
        static let tableViewTopPadding: CGFloat = 8
    }
}
