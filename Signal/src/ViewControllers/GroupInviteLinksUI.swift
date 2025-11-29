//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
public import SignalUI

public final class GroupInviteLinksUI {

    public static func openGroupInviteLink(_ url: URL, fromViewController: UIViewController) {
        AssertIsOnMainThread()

        let showInvalidInviteLinkAlert = {
            OWSActionSheets.showActionSheet(title: OWSLocalizedString("GROUP_LINK_INVALID_GROUP_INVITE_LINK_ERROR_TITLE",
                                                                     comment: "Title for the 'invalid group invite link' alert."),
                                            message: OWSLocalizedString("GROUP_LINK_INVALID_GROUP_INVITE_LINK_ERROR_MESSAGE",
                                                                      comment: "Message for the 'invalid group invite link' alert."))
        }

        guard let groupInviteLinkInfo = GroupInviteLinkInfo.parseFrom(url) else {
            owsFailDebug("Invalid group invite link.")
            showInvalidInviteLinkAlert()
            return
        }

        let groupV2ContextInfo: GroupV2ContextInfo
        do {
            groupV2ContextInfo = try GroupV2ContextInfo.deriveFrom(masterKeyData: groupInviteLinkInfo.masterKey)
        } catch {
            owsFailDebug("Error: \(error)")
            showInvalidInviteLinkAlert()
            return
        }

        // If the group already exists in the database, open it.
        if
            let existingGroupThread = (SSKEnvironment.shared.databaseStorageRef.read { transaction in
                TSGroupThread.fetch(forGroupId: groupV2ContextInfo.groupId, tx: transaction)
            }),
            existingGroupThread.groupModel.groupMembership.isLocalUserFullMember || existingGroupThread.groupModel.groupMembership.isLocalUserRequestingMember
        {
            SignalApp.shared.presentConversationForThread(
                threadUniqueId: existingGroupThread.uniqueId,
                animated: true
            )
            return
        }

        let actionSheet = GroupInviteLinksActionSheet(groupInviteLinkInfo: groupInviteLinkInfo,
                                                      groupV2ContextInfo: groupV2ContextInfo)
        fromViewController.presentActionSheet(actionSheet)
    }
}

// MARK: -

private class GroupInviteLinksActionSheet: ActionSheetController {
    private let groupInviteLinkInfo: GroupInviteLinkInfo
    private let groupV2ContextInfo: GroupV2ContextInfo

    private var downloadedAvatar: (avatarUrlPath: String, avatarData: Data?)?

    // Group Preview UI elements.
    private let avatarView = AvatarImageView()
    private let groupNameLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.semiboldFont(ofSize: UIFont.dynamicTypeTitle1Clamped.pointSize * (13/14))
        label.textColor = .Signal.label
        // Reserve vertical space for group name.
        label.text = " "
        return label
    }()
    private let groupSubtitleLabel: UILabel = {
        let label = UILabel()
        label.font = .dynamicTypeSubheadline
        label.textColor = .Signal.secondaryLabel
        label.text = " "
        return label
    }()
    private let groupDescriptionPreview: GroupDescriptionPreviewView = {
        let view = GroupDescriptionPreviewView()
        view.font = .dynamicTypeSubheadline
        view.textColor = .Signal.secondaryLabel
        view.numberOfLines = 2
        view.textAlignment = .center
        view.isHidden = true
        return view
    }()
    private let messageLabel: UILabel = {
        let label = UILabel()
        label.font = .dynamicTypeBodyClamped
        label.textColor = .Signal.label
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.textAlignment = .center
        label.text = OWSLocalizedString(
            "GROUP_LINK_ACTION_SHEET_JOIN_MESSAGE",
            comment: "Message text for the 'group invite link' action sheet."
        )
        return label
    }()
    private lazy var joinButton = UIButton(
        configuration: .largePrimary(title: OWSLocalizedString(
            "GROUP_LINK_ACTION_SHEET_VIEW_JOIN_BUTTON",
            comment: "Label for the 'join' button in the 'group invite link' action sheet."
        )),
        primaryAction: UIAction { [weak self] _ in
            self?.didTapJoin()
        }
    )
    private lazy var groupPreviewView: UIView = {
        let textContentHMargin: CGFloat = 12

        // Group avatar at the top.
        let avatarViewContainer = UIView.container()
        avatarView.translatesAutoresizingMaskIntoConstraints = false
        avatarViewContainer.addSubview(avatarView)
        NSLayoutConstraint.activate([
            avatarView.topAnchor.constraint(equalTo: avatarViewContainer.topAnchor),
            avatarView.leadingAnchor.constraint(greaterThanOrEqualTo: avatarViewContainer.leadingAnchor),
            avatarView.centerXAnchor.constraint(equalTo: avatarViewContainer.centerXAnchor),
            avatarView.bottomAnchor.constraint(equalTo: avatarViewContainer.bottomAnchor),
        ])

        // Multiple text lines in the middle.
        let textStack = UIStackView(arrangedSubviews: [
            groupNameLabel,
            groupSubtitleLabel,
            groupDescriptionPreview,
        ])
        textStack.axis = .vertical
        textStack.alignment = .center
        textStack.setCustomSpacing(8, after: groupNameLabel)
        textStack.setCustomSpacing(10, after: groupSubtitleLabel)
        textStack.isLayoutMarginsRelativeArrangement = true
        textStack.directionalLayoutMargins = NSDirectionalEdgeInsets(hMargin: textContentHMargin, vMargin: 0)

        let messageLabelContainer = UIView()
        messageLabelContainer.layoutMargins = .init(hMargin: textContentHMargin, vMargin: 0)
        messageLabelContainer.addSubview(messageLabel)
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            messageLabel.topAnchor.constraint(equalTo: messageLabelContainer.layoutMarginsGuide.topAnchor),
            messageLabel.leadingAnchor.constraint(equalTo: messageLabelContainer.layoutMarginsGuide.leadingAnchor),
            messageLabel.trailingAnchor.constraint(equalTo: messageLabelContainer.layoutMarginsGuide.trailingAnchor),
            messageLabel.bottomAnchor.constraint(equalTo: messageLabelContainer.layoutMarginsGuide.bottomAnchor),
        ])

        // "Join" button at the bottom.

        let view = UIStackView(arrangedSubviews: [
            avatarViewContainer,
            textStack,
            messageLabelContainer,
            joinButton
        ])
        view.axis = .vertical
        view.spacing = 20
        view.setCustomSpacing(12, after: avatarViewContainer)
        view.isLayoutMarginsRelativeArrangement = true
        view.directionalLayoutMargins = .init(top: 24, leading: 0, bottom: 2, trailing: 0)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    // Loading state UI elements.
    private let activityIndicator = UIActivityIndicatorView(style: .large)
    private lazy var loadingLinkInfoView: UIView = {
        activityIndicator.tintColor = .Signal.secondaryLabel
        let label = UILabel()
        label.text = OWSLocalizedString(
            "GROUP_LINK_ACTION_SHEET_VIEW_LOADING_TITLE",
            comment: "Label indicating that the group info is being loaded in the 'group invite link' action sheet."
        )
        label.textColor = .Signal.secondaryLabel
        label.font = .dynamicTypeSubheadline
        let vStack = UIStackView(arrangedSubviews: [activityIndicator, label])
        vStack.spacing = 10
        vStack.axis = .vertical
        vStack.alignment = .center
        vStack.translatesAutoresizingMaskIntoConstraints = false
        let view = UIView()
        view.addSubview(vStack)
        NSLayoutConstraint.activate([
            vStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            vStack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            vStack.trailingAnchor.constraint(greaterThanOrEqualTo: view.trailingAnchor),
            vStack.topAnchor.constraint(greaterThanOrEqualTo: view.topAnchor),
        ])
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var cancelAction = ActionSheetAction(
        title: CommonStrings.cancelButton,
        style: .cancel,
        handler: { [weak self] _ in
            self?.didTapCancel()
        }
    )

    init(groupInviteLinkInfo: GroupInviteLinkInfo, groupV2ContextInfo: GroupV2ContextInfo) {
        self.groupInviteLinkInfo = groupInviteLinkInfo
        self.groupV2ContextInfo = groupV2ContextInfo

        super.init()

        isCancelable = true
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let avatarBuilder = SSKEnvironment.shared.avatarBuilderRef
        let databaseStorage = SSKEnvironment.shared.databaseStorageRef

        avatarView.image = databaseStorage.read { tx in
            avatarBuilder.defaultAvatarImage(
                forGroupId: groupV2ContextInfo.groupId.serialize(),
                diameterPoints: Self.avatarSize,
                transaction: tx
            )
        }
        avatarView.autoSetDimension(.width, toSize: CGFloat(Self.avatarSize))

        groupPreviewView.isHidden = true

        let header = UIView()
        header.addSubview(groupPreviewView)
        header.addSubview(loadingLinkInfoView)
        NSLayoutConstraint.activate([
            groupPreviewView.topAnchor.constraint(equalTo: header.topAnchor),
            groupPreviewView.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            groupPreviewView.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            groupPreviewView.bottomAnchor.constraint(equalTo: header.bottomAnchor),

            loadingLinkInfoView.topAnchor.constraint(equalTo: header.topAnchor),
            loadingLinkInfoView.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            loadingLinkInfoView.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            loadingLinkInfoView.bottomAnchor.constraint(equalTo: header.bottomAnchor),
        ])
        self.customHeader = header

        addAction(cancelAction)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        activityIndicator.startAnimating()
        loadLinkPreview()
    }

    // MARK: - Load invite link preview

    private enum LinkPreviewLoadResult {
        case success(GroupInviteLinkPreview)
        case expiredLink
        case failure(Error)
    }

    private static let avatarSize: UInt = 88

    private func loadLinkPreview() {
        Task { [weak self, groupInviteLinkInfo, groupV2ContextInfo] in
            do {
                let groupInviteLinkPreview = try await SSKEnvironment.shared.groupsV2Ref.fetchGroupInviteLinkPreviewAndRefreshGroup(
                    inviteLinkPassword: groupInviteLinkInfo.inviteLinkPassword,
                    groupSecretParams: groupV2ContextInfo.groupSecretParams
                )
                self?.applyLinkPreviewLoadResult(.success(groupInviteLinkPreview))

                guard self != nil else {
                    return
                }

                if let avatarUrlPath = groupInviteLinkPreview.avatarUrlPath {
                    do {
                        let avatarData = try await SSKEnvironment.shared.groupsV2Ref.fetchGroupInviteLinkAvatar(
                            avatarUrlPath: avatarUrlPath,
                            groupSecretParams: groupV2ContextInfo.groupSecretParams
                        )
                        guard DataImageSource(avatarData).ows_isValidImage else {
                            throw OWSAssertionError("Invalid group avatar.")
                        }
                        guard let image = UIImage(data: avatarData) else {
                            throw OWSAssertionError("Could not load group avatar.")
                        }
                        self?.downloadedAvatar = (avatarUrlPath, avatarData: avatarData)
                        self?.avatarView.image = image
                    } catch {
                        self?.downloadedAvatar = (avatarUrlPath, avatarData: nil)
                        owsFailDebugUnlessNetworkFailure(error)
                    }
                }
            } catch GroupsV2Error.expiredGroupInviteLink {
                self?.applyLinkPreviewLoadResult(.expiredLink)
            } catch GroupsV2Error.localUserBlockedFromJoining {
                Logger.warn("User blocked")
                self?.dismiss(animated: true, completion: {
                    OWSActionSheets.showActionSheet(
                        title: OWSLocalizedString(
                            "GROUP_LINK_ACTION_SHEET_VIEW_CANNOT_JOIN_GROUP_TITLE",
                            comment: "Title indicating that you cannot join a group in the 'group invite link' action sheet."
                        ),
                        message: OWSLocalizedString(
                            "GROUP_LINK_ACTION_SHEET_VIEW_BLOCKED_FROM_JOINING_SUBTITLE",
                            comment: "Subtitle indicating that the local user has been blocked from joining the group"
                        )
                    )
                })
            } catch {
                self?.applyLinkPreviewLoadResult(.failure(error))
            }
        }
    }

    private func applyLinkPreviewLoadResult(_ result: LinkPreviewLoadResult) {
        switch result {
        case .success(let groupInviteLinkPreview):
            switch groupInviteLinkPreview.addFromInviteLinkAccess {
            case .any:
                // view is already configured for this state
                break

            case .administrator:
                messageLabel.text = OWSLocalizedString(
                    "GROUP_LINK_ACTION_SHEET_JOIN_MESSAGE_W_REQUEST",
                    comment: "Message text for the 'group invite link' action sheet, if the user will be requesting to join."
                )
                joinButton.configuration?.title = OWSLocalizedString(
                    "GROUP_LINK_ACTION_SHEET_VIEW_REQUEST_TO_JOIN_BUTTON",
                    comment: "Label for the 'request to join' button in the 'group invite link' action sheet."
                )

            case .member, .unsatisfiable, .unknown:
                owsFailDebug("Invalid addFromInviteLinkAccess!")
            }

            let groupName = groupInviteLinkPreview.title.filterForDisplay.nilIfEmpty ?? TSGroupThread.defaultGroupName
            groupNameLabel.text = groupName
            groupSubtitleLabel.text = GroupViewUtils.formatGroupMembersLabel(
                memberCount: Int(groupInviteLinkPreview.memberCount)
            )
            if let descriptionText = groupInviteLinkPreview.descriptionText?.filterForDisplay.nilIfEmpty {
                groupDescriptionPreview.descriptionText = descriptionText
                groupDescriptionPreview.groupName = groupName
                groupDescriptionPreview.isHidden = false
            }

            groupPreviewView.isHidden = false
            loadingLinkInfoView.isHidden = true

        case .expiredLink:
            setTitle(
                OWSLocalizedString(
                    "GROUP_LINK_ACTION_SHEET_VIEW_CANNOT_JOIN_GROUP_TITLE",
                    comment: "Title indicating that you cannot join a group in the 'group invite link' action sheet."
                ),
                message: OWSLocalizedString(
                    "GROUP_LINK_ACTION_SHEET_VIEW_EXPIRED_LINK_SUBTITLE",
                    comment: "Subtitle indicating that the group invite link has expired in the 'group invite link' action sheet."
                )
            )
            customHeader = nil

        case .failure(let error):
            owsFailDebugUnlessNetworkFailure(error)

            /// We don't know what went wrong, but existing behavior at the time
            /// of writing is that tapping the join button will make another
            /// attempt to load the link preview, and automatically attempt to
            /// join (or request to join) if possible. If this was a transient
            /// network error, for example, then you may be able to recover by
            /// hitting the join button.
            ///
            /// To that end, we'll enable it and default-populate it with the
            /// "join" strings (since we won't know until that re-attempt if it
            /// should've actually been "request to join").

            groupPreviewView.isHidden = false
            loadingLinkInfoView.isHidden = true
        }
    }

    // MARK: - Actions

    private func didTapCancel() {
        dismiss(animated: true)
    }

    private func showActionSheet(
        title: String?,
        message: String? = nil,
        buttonTitle: String? = nil,
        buttonAction: ActionSheetAction.Handler? = nil
    ) {
        OWSActionSheets.showActionSheet(
            title: title,
            message: message,
            buttonTitle: buttonTitle,
            buttonAction: buttonAction,
            fromViewController: self
        )
    }

    private func didTapJoin() {
        AssertIsOnMainThread()

        Logger.info("")

        // If we've already downloaded the avatar, reuse it.
        let downloadedAvatar = self.downloadedAvatar

        ModalActivityIndicatorViewController.present(
            fromViewController: self,
            canCancel: false,
            asyncBlock: { [weak self, groupInviteLinkInfo, groupV2ContextInfo] modal in
                do {
                    try await GroupManager.joinGroupViaInviteLink(
                        secretParams: groupV2ContextInfo.groupSecretParams,
                        inviteLinkPassword: groupInviteLinkInfo.inviteLinkPassword,
                        downloadedAvatar: downloadedAvatar
                    )

                    modal.dismiss {
                        AssertIsOnMainThread()
                        self?.dismiss(animated: true) {
                            AssertIsOnMainThread()
                            let groupThread = SSKEnvironment.shared.databaseStorageRef.read { tx in
                                // We successfully joined, so we must be able to find the TSGroupThread.
                                return TSGroupThread.fetch(forGroupId: groupV2ContextInfo.groupId, tx: tx)!
                            }
                            SignalApp.shared.presentConversationForThread(
                                threadUniqueId: groupThread.uniqueId,
                                animated: true
                            )
                        }
                    }
                } catch {
                    Logger.warn("Error: \(error)")

                    modal.dismiss {
                        AssertIsOnMainThread()

                        self?.showActionSheet(
                            title: OWSLocalizedString(
                                "GROUP_LINK_ACTION_SHEET_VIEW_CANNOT_JOIN_GROUP_TITLE",
                                comment: "Title indicating that you cannot join a group in the 'group invite link' action sheet."
                            ),
                            message: {
                                switch error {
                                case GroupsV2Error.expiredGroupInviteLink:
                                    return OWSLocalizedString(
                                        "GROUP_LINK_ACTION_SHEET_VIEW_EXPIRED_LINK_SUBTITLE",
                                        comment: "Subtitle indicating that the group invite link has expired in the 'group invite link' action sheet."
                                    )
                                case GroupsV2Error.localUserBlockedFromJoining:
                                    return OWSLocalizedString(
                                        "GROUP_LINK_ACTION_SHEET_VIEW_BLOCKED_FROM_JOINING_SUBTITLE",
                                        comment: "Subtitle indicating that the local user has been blocked from joining the group"
                                    )
                                case _ where error.isNetworkFailureOrTimeout:
                                    return OWSLocalizedString(
                                        "GROUP_LINK_COULD_NOT_REQUEST_TO_JOIN_GROUP_DUE_TO_NETWORK_ERROR_MESSAGE",
                                        comment: "Error message the attempt to request to join the group failed due to network connectivity."
                                    )
                                default:
                                    return OWSLocalizedString(
                                        "GROUP_LINK_COULD_NOT_REQUEST_TO_JOIN_GROUP_ERROR_MESSAGE",
                                        comment: "Error message the attempt to request to join the group failed."
                                    )
                                }
                            }()
                        )
                    }
                }
            }
        )
    }
}
