//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalRingRTC
import SignalMessaging

@objc
class GroupCallMemberSheet: InteractiveSheetViewController {
    override var interactiveScrollViews: [UIScrollView] { [tableView] }

    let tableView = UITableView(frame: .zero, style: .grouped)
    let call: SignalCall

    override var sheetBackgroundColor: UIColor {
        UIAccessibility.isReduceTransparencyEnabled ? .ows_blackAlpha80 : .ows_blackAlpha40
    }

    init(call: SignalCall) {
        self.call = call

        let blurEffect: UIBlurEffect?
        if UIAccessibility.isReduceTransparencyEnabled {
            blurEffect = nil
        } else {
            blurEffect = .init(style: .dark)
        }

        super.init(blurEffect: blurEffect)
        call.addObserverAndSyncState(observer: self)
    }

    public required init() {
        fatalError("init() has not been implemented")
    }

    deinit { call.removeObserver(self) }

    // MARK: -

    override public func viewDidLoad() {
        super.viewDidLoad()

        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.tableHeaderView = UIView(frame: CGRect(origin: .zero, size: CGSize(width: 0, height: CGFloat.leastNormalMagnitude)))
        contentView.addSubview(tableView)
        tableView.autoPinEdgesToSuperviewEdges()

        tableView.register(GroupCallMemberCell.self, forCellReuseIdentifier: GroupCallMemberCell.reuseIdentifier)
        tableView.register(GroupCallEmptyCell.self, forCellReuseIdentifier: GroupCallEmptyCell.reuseIdentifier)

        updateMembers()
    }

    // MARK: -

    struct JoinedMember {
        let address: SignalServiceAddress
        let displayName: String
        let comparableName: String
        let isAudioMuted: Bool?
        let isVideoMuted: Bool?
        let isPresenting: Bool?
    }

    private var sortedMembers = [JoinedMember]()
    func updateMembers() {
        let unsortedMembers: [JoinedMember] = databaseStorage.read { transaction in
            var members = [JoinedMember]()

            if self.call.groupCall.localDeviceState.joinState == .joined {
                members += self.call.groupCall.remoteDeviceStates.values.map { member in
                    let displayName: String
                    let comparableName: String
                    if member.address.isLocalAddress {
                        displayName = NSLocalizedString(
                            "GROUP_CALL_YOU_ON_ANOTHER_DEVICE",
                            comment: "Text describing the local user in the group call members sheet when connected from another device."
                        )
                        comparableName = displayName
                    } else {
                        displayName = self.contactsManager.displayName(for: member.address, transaction: transaction)
                        comparableName = self.contactsManager.comparableName(for: member.address, transaction: transaction)
                    }

                    return JoinedMember(
                        address: member.address,
                        displayName: displayName,
                        comparableName: comparableName,
                        isAudioMuted: member.audioMuted,
                        isVideoMuted: member.videoMuted,
                        isPresenting: member.presenting
                    )
                }

                guard let localAddress = self.tsAccountManager.localAddress else { return members }

                let displayName = CommonStrings.you
                let comparableName = displayName

                members.append(JoinedMember(
                    address: localAddress,
                    displayName: displayName,
                    comparableName: comparableName,
                    isAudioMuted: self.call.groupCall.isOutgoingAudioMuted,
                    isVideoMuted: self.call.groupCall.isOutgoingVideoMuted,
                    isPresenting: false
                ))
            } else {
                // If we're not yet in the call, `remoteDeviceStates` will not exist.
                // We can get the list of joined members still, provided we are connected.
                members += self.call.groupCall.peekInfo?.joinedMembers.map { uuid in
                    let address = SignalServiceAddress(uuid: uuid)
                    let displayName = self.contactsManager.displayName(for: address, transaction: transaction)
                    let comparableName = self.contactsManager.comparableName(for: address, transaction: transaction)

                    return JoinedMember(
                        address: address,
                        displayName: displayName,
                        comparableName: comparableName,
                        isAudioMuted: nil,
                        isVideoMuted: nil,
                        isPresenting: nil
                    )
                } ?? []
            }

            return members
        }

        sortedMembers = unsortedMembers.sorted { $0.comparableName.caseInsensitiveCompare($1.comparableName) == .orderedAscending }

        tableView.reloadData()
    }
}

extension GroupCallMemberSheet: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return sortedMembers.count > 0 ? sortedMembers.count : 1
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard !sortedMembers.isEmpty else {
            return tableView.dequeueReusableCell(withIdentifier: GroupCallEmptyCell.reuseIdentifier, for: indexPath)
        }

        let cell = tableView.dequeueReusableCell(withIdentifier: GroupCallMemberCell.reuseIdentifier, for: indexPath)

        guard let memberCell = cell as? GroupCallMemberCell else {
            owsFailDebug("unexpected cell type")
            return cell
        }

        guard let member = sortedMembers[safe: indexPath.row] else {
            owsFailDebug("missing member")
            return cell
        }

        memberCell.configure(item: member)

        return memberCell
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let label = UILabel()
        label.font = UIFont.ows_dynamicTypeSubheadlineClamped.ows_semibold
        label.textColor = Theme.darkThemePrimaryColor

        if sortedMembers.count > 0 {
            let formatString = NSLocalizedString(
                "GROUP_CALL_IN_THIS_CALL_%d", tableName: "PluralAware",
                comment: "String indicating how many people are current in the call"
            )
            label.text = String.localizedStringWithFormat(formatString, sortedMembers.count)
        } else {
            label.text = nil
        }

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
}

// MARK: -

extension GroupCallMemberSheet: CallObserver {
    func groupCallLocalDeviceStateChanged(_ call: SignalCall) {
        AssertIsOnMainThread()
        owsAssertDebug(call.isGroupCall)

        updateMembers()
    }

    func groupCallRemoteDeviceStatesChanged(_ call: SignalCall) {
        AssertIsOnMainThread()
        owsAssertDebug(call.isGroupCall)

        updateMembers()
    }

    func groupCallPeekChanged(_ call: SignalCall) {
        AssertIsOnMainThread()
        owsAssertDebug(call.isGroupCall)

        updateMembers()
    }

    func groupCallEnded(_ call: SignalCall, reason: GroupCallEndReason) {
        AssertIsOnMainThread()
        owsAssertDebug(call.isGroupCall)

        updateMembers()
    }
}

private class GroupCallMemberCell: UITableViewCell {
    static let reuseIdentifier = "GroupCallMemberCell"

    let avatarView = ConversationAvatarView(
        sizeClass: .thirtySix,
        localUserDisplayMode: .asUser,
        badged: false)
    let nameLabel = UILabel()
    let videoMutedIndicator = UIImageView()
    let audioMutedIndicator = UIImageView()
    let presentingIndicator = UIImageView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        backgroundColor = .clear
        selectionStyle = .none
        layoutMargins = UIEdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)

        nameLabel.font = .ows_dynamicTypeBody

        audioMutedIndicator.contentMode = .scaleAspectFit
        audioMutedIndicator.setTemplateImage(#imageLiteral(resourceName: "mic-off-solid-28"), tintColor: .ows_white)
        audioMutedIndicator.autoSetDimensions(to: CGSize(square: 16))
        audioMutedIndicator.setContentHuggingHorizontalHigh()
        let audioMutedWrapper = UIView()
        audioMutedWrapper.addSubview(audioMutedIndicator)
        audioMutedIndicator.autoPinEdgesToSuperviewEdges()

        videoMutedIndicator.contentMode = .scaleAspectFit
        videoMutedIndicator.setTemplateImage(#imageLiteral(resourceName: "video-off-solid-28"), tintColor: .ows_white)
        videoMutedIndicator.autoSetDimensions(to: CGSize(square: 16))
        videoMutedIndicator.setContentHuggingHorizontalHigh()

        presentingIndicator.contentMode = .scaleAspectFit
        presentingIndicator.setTemplateImage(#imageLiteral(resourceName: "share-screen-solid-28"), tintColor: .ows_white)
        presentingIndicator.autoSetDimensions(to: CGSize(square: 16))
        presentingIndicator.setContentHuggingHorizontalHigh()

        // We share a wrapper for video muted and presenting states
        // as they render in the same column.
        let videoMutedAndPresentingWrapper = UIView()
        videoMutedAndPresentingWrapper.addSubview(videoMutedIndicator)
        videoMutedIndicator.autoPinEdgesToSuperviewEdges()

        videoMutedAndPresentingWrapper.addSubview(presentingIndicator)
        presentingIndicator.autoPinEdgesToSuperviewEdges()

        let stackView = UIStackView(arrangedSubviews: [
            avatarView,
            UIView.spacer(withWidth: 8),
            nameLabel,
            UIView.spacer(withWidth: 16),
            videoMutedAndPresentingWrapper,
            UIView.spacer(withWidth: 16),
            audioMutedWrapper
        ])
        stackView.axis = .horizontal
        stackView.alignment = .center
        contentView.addSubview(stackView)
        stackView.autoPinEdgesToSuperviewMargins()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(item: GroupCallMemberSheet.JoinedMember) {
        nameLabel.textColor = Theme.darkThemePrimaryColor

        videoMutedIndicator.isHidden = item.isVideoMuted != true || item.isPresenting == true
        audioMutedIndicator.isHidden = item.isAudioMuted != true
        presentingIndicator.isHidden = item.isPresenting != true

        nameLabel.text = item.displayName
        avatarView.updateWithSneakyTransactionIfNecessary { config in
            config.dataSource = .address(item.address)
        }
    }
}

private class GroupCallEmptyCell: UITableViewCell {
    static let reuseIdentifier = "GroupCallEmptyCell"

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        backgroundColor = .clear
        selectionStyle = .none

        layoutMargins = UIEdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)

        let imageView = UIImageView(image: #imageLiteral(resourceName: "sad-cat"))
        imageView.contentMode = .scaleAspectFit
        contentView.addSubview(imageView)
        imageView.autoSetDimensions(to: CGSize(square: 160))
        imageView.autoHCenterInSuperview()
        imageView.autoPinTopToSuperviewMargin(withInset: 32)

        let label = UILabel()
        label.font = .ows_dynamicTypeSubheadlineClamped
        label.textColor = Theme.darkThemePrimaryColor
        label.text = NSLocalizedString("GROUP_CALL_NOBODY_IS_IN_YET",
                                       comment: "Text explaining to the user that nobody has joined this call yet.")
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.textAlignment = .center
        contentView.addSubview(label)
        label.autoPinWidthToSuperviewMargins()
        label.autoPinBottomToSuperviewMargin()
        label.autoPinEdge(.top, to: .bottom, of: imageView, withOffset: 16)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
