//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit

@objc
class BlockingGroupMigrationView: UIStackView {

    private let thread: TSThread

    private weak var fromViewController: UIViewController?

    init(threadViewModel: ThreadViewModel, fromViewController: UIViewController) {
        let thread = threadViewModel.threadRecord
        self.thread = thread
        owsAssertDebug(thread as? TSGroupThread != nil)
        self.fromViewController = fromViewController

        super.init(frame: .zero)

        createContents()
    }

    private func createContents() {
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

        let backgroundView = UIView()
        backgroundView.backgroundColor = Theme.backgroundColor
        addSubview(backgroundView)
        backgroundView.autoPinEdgesToSuperviewEdges()

        let format = NSLocalizedString("GROUPS_LEGACY_GROUP_BLOCKING_MIGRATION_FORMAT",
                                       comment: "Format for indicator that a group cannot be used until it is migrated. Embeds {{ a \"learn more\" link. }}.")
        let learnMoreText = CommonStrings.learnMore
        let text = String(format: format, learnMoreText)
        let attributedString = NSMutableAttributedString(string: text)
        attributedString.setAttributes([
            .foregroundColor: Theme.accentBlueColor
        ],
        forSubstring: learnMoreText)

        let label = UILabel()
        label.font = .ows_dynamicTypeSubheadlineClamped
        label.textColor = Theme.secondaryTextAndIconColor
        label.attributedText = attributedString
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.isUserInteractionEnabled = true
        label.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTapLearnMore)))
        addArrangedSubview(label)

        let continueButton = OWSFlatButton.button(title: CommonStrings.continueButton,
                                                 font: UIFont.ows_dynamicTypeBody.ows_semibold,
                                                 titleColor: .white,
                                                 backgroundColor: .ows_accentBlue,
                                                 target: self,
                                                 selector: #selector(didTapContinueButton))
        continueButton.autoSetHeightUsingFont()
        addArrangedSubview(continueButton)
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        return .zero
    }

    // MARK: -

    @objc
    public func didTapLearnMore() {
        guard let fromViewController = self.fromViewController else {
            owsFailDebug("Missing fromViewController.")
            return
        }
        LegacyGroupViewLearnMoreView().present(fromViewController: fromViewController)
    }

    private func blockingMigrationInfo(groupThread: TSGroupThread) -> GroupsV2MigrationInfo? {
        guard let groupThread = thread as? TSGroupThread,
              groupThread.isGroupV1Thread else {
            return nil
        }

        // migrationInfoForManualMigrationWithGroupThread uses
        // a transaction, so we try to avoid calling it.
        return GroupsV2Migration.migrationInfoForManualMigration(groupThread: groupThread)
    }

    @objc
    func didTapContinueButton(_ sender: UIButton) {
        guard let groupThread = thread as? TSGroupThread else {
            owsFailDebug("Invalid thread.")
            return
        }
        guard let fromViewController = self.fromViewController else {
            owsFailDebug("Missing fromViewController.")
            return
        }
        guard let migrationInfo = blockingMigrationInfo(groupThread: groupThread) else {
            owsFailDebug("Missing migrationInfo.")
            return
        }
        let mode = GroupMigrationActionSheet.Mode.upgradeGroup(migrationInfo: migrationInfo)
        let view = GroupMigrationActionSheet(groupThread: groupThread, mode: mode)
        view.present(fromViewController: fromViewController)
    }
}
