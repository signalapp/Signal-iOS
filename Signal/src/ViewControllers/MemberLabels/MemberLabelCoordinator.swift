//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalServiceKit
import SignalUI

protocol MemberLabelViewControllerPresenter: UIViewController {
    func reloadMemberLabelIfNeeded()
}

/// Responsible for flows related to setting or editing a group member label.
/// Since users can only set/edit their own member label, this is local-user specific.
/// See also `MemberLabelViewController` which allows a user to set/edit their own member label.
public final class MemberLabelCoordinator {
    weak var presenter: MemberLabelViewControllerPresenter?

    var groupModel: TSGroupModelV2
    private let memberLabel: MemberLabel?
    private let kvStore: NewKeyValueStore
    private let groupNameColors: GroupNameColors
    private let localIdentifiers: LocalIdentifiers
    private let db: DB
    private let profileManager: ProfileManager

    private enum KVStoreKeys {
        static let ignoreMemberLabelAboutOverrideKey = "ignoreMemberLabelAboutOverrideKeyV2"
    }

    convenience init(
        groupModel: TSGroupModelV2,
        groupNameColors: GroupNameColors,
        localIdentifiers: LocalIdentifiers,
    ) {
        self.init(
            groupModel: groupModel,
            groupNameColors: groupNameColors,
            localIdentifiers: localIdentifiers,
            db: DependenciesBridge.shared.db,
            profileManager: SSKEnvironment.shared.profileManagerRef,
        )
    }

    init(
        groupModel: TSGroupModelV2,
        groupNameColors: GroupNameColors,
        localIdentifiers: LocalIdentifiers,
        db: DB,
        profileManager: ProfileManager,
    ) {
        self.groupModel = groupModel
        self.memberLabel = groupModel.groupMembership.localUserMemberLabel
        self.groupNameColors = groupNameColors
        self.localIdentifiers = localIdentifiers
        self.db = db
        self.profileManager = profileManager
        self.kvStore = NewKeyValueStore(collection: "MemberLabelCoordinator")
    }

    func presentWithEducationSheet(
        localUserHasMemberLabel: Bool,
        canEditMemberLabel: Bool,
    ) {
        var editBlock: (() -> Void)?
        if canEditMemberLabel {
            editBlock = { [weak self] in
                self?.present()
            }
        }

        let hero = MemberLabelEducationHeroSheet(
            hasMemberLabel: localUserHasMemberLabel,
            editMemberLabelHandler: editBlock,
        )
        presenter?.present(hero, animated: true)
    }

    private func buildGroupMemberLabelsWithoutLocalUser() -> [SignalServiceAddress: MemberLabelForRendering] {
        var memberLabels: [SignalServiceAddress: MemberLabelForRendering] = [:]
        let groupMembership = groupModel.groupMembership
        for member in groupMembership.fullMembers {
            guard
                !localIdentifiers.contains(address: member),
                let aci = member.aci,
                let memberLabel = groupMembership.memberLabel(for: aci)
            else {
                continue
            }
            let groupNameColor = groupNameColors.color(for: aci)
            let memberLabelForRendering = MemberLabelForRendering(
                label: memberLabel.labelForRendering(),
                groupNameColor: groupNameColor,
            )
            memberLabels[member] = memberLabelForRendering
        }
        return memberLabels
    }

    func present() {
        let memberLabelViewController = MemberLabelViewController(
            memberLabel: memberLabel?.label,
            emoji: memberLabel?.labelEmoji,
            groupNameColors: groupNameColors,
            groupMemberLabelsWithoutLocalUser: buildGroupMemberLabelsWithoutLocalUser(),
            groupModel: groupModel,
            db: db,
            contactManager: SSKEnvironment.shared.contactManagerImplRef,
        )
        memberLabelViewController.updateDelegate = self

        presenter?.present(OWSNavigationController(rootViewController: memberLabelViewController), animated: true)
    }

    private func showOverrideAboutWarningIfNeeded(localUserBio: String?) {
        let ignoreMemberLabelAboutOverrideKey = db.read { tx in
            let value = self.kvStore.fetchValue(
                Bool.self,
                forKey: KVStoreKeys.ignoreMemberLabelAboutOverrideKey,
                tx: tx,
            )
            return value == true
        }

        if localUserBio != nil, !ignoreMemberLabelAboutOverrideKey {
            let hero = MemberLabelAboutOverrideHeroSheet(
                dontShowAgainHandler: { [weak self] in
                    self?.db.write { tx in
                        self?.kvStore.writeValue(
                            true,
                            forKey: KVStoreKeys.ignoreMemberLabelAboutOverrideKey,
                            tx: tx,
                        )
                    }
                },
            )
            presenter?.present(hero, animated: true)
        }
    }

    private func showMemberLabelSaveFailed() {
        OWSActionSheets.showActionSheet(
            title: OWSLocalizedString(
                "MEMBER_LABEL_FAIL_TO_SAVE",
                comment: "Error indicating member label could not save.",
            ),
            message: OWSLocalizedString(
                "CHECK_YOUR_CONNECTION_TRY_AGAIN_WARNING",
                comment: "Message indicating a user should check connection and try again.",
            ),
        )
    }

    func updateLabelForLocalUser(memberLabel: MemberLabel?) {
        Logger.info("")
        guard let presenter else { return }
        let changeLabelBlock: () -> Void = {
            Task { @MainActor in
                Logger.info("")
                let localUserBio = self.db.read(block: { tx -> String? in
                    return self.profileManager.userProfile(for: SignalServiceAddress(self.localIdentifiers.aci), tx: tx)?.bioForDisplay
                })

                do {
                    try await ModalActivityIndicatorViewController.presentAndPropagateResult(
                        from: presenter,
                        title: CommonStrings.updatingModal,
                        wrappedAsyncBlock: {
                            try await GroupManager.changeMemberLabel(
                                groupModel: self.groupModel,
                                aci: self.localIdentifiers.aci,
                                label: memberLabel,
                            )
                        },
                    )

                    if memberLabel != nil {
                        self.showOverrideAboutWarningIfNeeded(localUserBio: localUserBio)
                    }
                    presenter.reloadMemberLabelIfNeeded()
                } catch {
                    self.showMemberLabelSaveFailed()
                }
            }
        }

        if let p = presenter.presentedViewController {
            p.dismiss(animated: true, completion: {
                changeLabelBlock()
            })
            return
        }
        changeLabelBlock()
    }
}
