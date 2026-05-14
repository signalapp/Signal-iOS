//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import BonMot
import Foundation
import SignalServiceKit
import UIKit

public class MyStorySettingsViewController: OWSTableViewController2, MyStorySettingsDataSourceDelegate {

    private lazy var dataSource = MyStorySettingsDataSource(delegate: self)

    override public func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString("MY_STORY_SETTINGS_TITLE", comment: "Title for the my story settings view")

        reloadTableContents()
    }

    func reloadTableContents() {
        self.contents = dataSource.generateTableContents(style: .fullscreen)
    }
}

public class MyStorySettingsSheetViewController: OWSTableSheetViewController, MyStorySettingsDataSourceDelegate {

    private lazy var dataSource = MyStorySettingsDataSource(delegate: self)

    private var willDisappear: (() -> Void)?

    public init(willDisappear: (() -> Void)? = nil) {
        self.willDisappear = willDisappear
        super.init()
    }

    override public func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        willDisappear?()
    }

    override public func updateTableContents(shouldReload: Bool = true) {
        let contents = dataSource.generateTableContents(style: .sheet)
        self.tableViewController.setContents(contents, shouldReload: shouldReload)
    }

    func reloadTableContents() {
        self.updateTableContents(shouldReload: true)
    }
}

private protocol MyStorySettingsDataSourceDelegate: AnyObject, UIViewController {
    func reloadTableContents()
}

private class MyStorySettingsDataSource: NSObject {

    private weak var delegate: MyStorySettingsDataSourceDelegate?

    init(delegate: MyStorySettingsDataSourceDelegate) {
        super.init()
        self.delegate = delegate
    }

    enum Style {
        /// Omits section titles, replies toggle, and learn more text. Row subtitles are omitted.
        case sheet
        /// Shows all sections and headers.
        case fullscreen
    }

    func generateTableContents(style: Style) -> OWSTableContents {
        let contents = OWSTableContents()

        let databaseStorage = SSKEnvironment.shared.databaseStorageRef
        let storyRecipientStore = DependenciesBridge.shared.storyRecipientStore

        let (
            hasSetMyStoriesPrivacy,
            myStoryThread,
            myStoryThreadRecipientIds,
        ) = databaseStorage.read { transaction -> (Bool, TSPrivateStoryThread, [SignalRecipient.RowId]) in
            let myStoryThread: TSPrivateStoryThread = TSPrivateStoryThread.getMyStory(transaction: transaction)
            return (
                StoryManager.hasSetMyStoriesPrivacy(transaction: transaction),
                myStoryThread,
                failIfThrows {
                    return try storyRecipientStore.fetchRecipientIds(forStoryThreadId: myStoryThread.sqliteRowId!, tx: transaction)
                },
            )
        }

        let visibilitySection = OWSTableSection()
        visibilitySection.separatorInsetLeading = OWSTableViewController2.cellHInnerMargin + 32
        switch style {
        case .sheet:
            let headerView = SheetHeaderView(frame: .zero, dataSource: self)
            headerView.doneButton.isEnabled = hasSetMyStoriesPrivacy
            visibilitySection.customHeaderView = headerView
        case .fullscreen:
            visibilitySection.headerTitle = OWSLocalizedString(
                "STORY_SETTINGS_WHO_CAN_VIEW_THIS_HEADER",
                comment: "Section header for the 'viewers' section on the 'story settings' view",
            )
            let footerTextView = makeWhoCanViewThisTextView(for: style)
            let footerContainer = UIView()
            footerContainer.addSubview(footerTextView)
            footerTextView.autoPinEdgesToSuperviewEdges(with: .init(hMargin: 16, vMargin: 16))
            visibilitySection.customFooterView = footerContainer
        }
        contents.add(visibilitySection)

        let storyViewMode: TSThreadStoryViewMode?
        if hasSetMyStoriesPrivacy {
            storyViewMode = myStoryThread.storyViewMode
        } else {
            // No option should be selected if story privacy settings are unset.
            storyViewMode = nil
        }

        do {
            let isSelected = storyViewMode == .blockList && myStoryThreadRecipientIds.isEmpty
            let detailText: String?
            if isSelected {
                let formatString = OWSLocalizedString(
                    "MY_STORIES_SETTINGS_VISIBILITY_ALL_SIGNAL_CONNECTIONS_SUBTITLE_%d",
                    tableName: "PluralAware",
                    comment: "Subtitle for the visibility option. Embeds number of allowed members",
                )
                detailText = String.localizedStringWithFormat(formatString, myStoryThread.recipientAddressesWithSneakyTransaction.count)
            } else {
                detailText = nil
            }
            visibilitySection.add(buildVisibilityItem(
                title: OWSLocalizedString(
                    "MY_STORIES_SETTINGS_VISIBILITY_ALL_SIGNAL_CONNECTIONS_TITLE",
                    comment: "Title for the visibility option",
                ),
                detailText: detailText,
                isSelected: isSelected,
                accessory: .button(title: CommonStrings.viewButton, action: { [weak self] in
                    let vc = AllSignalConnectionsViewController()
                    self?.delegate?.presentFormSheet(OWSNavigationController(rootViewController: vc), animated: true)
                }),
            ) { [weak self] in
                SSKEnvironment.shared.databaseStorageRef.write { transaction in
                    myStoryThread.updateWithStoryViewMode(
                        .blockList,
                        storyRecipientIds: .setTo([]),
                        updateStorageService: true,
                        transaction: transaction,
                    )
                }
                self?.delegate?.reloadTableContents()
            })
        }

        do {
            let isSelected = storyViewMode == .blockList && !myStoryThreadRecipientIds.isEmpty
            let detailText: String?
            if isSelected {
                let formatString = OWSLocalizedString(
                    "MY_STORIES_SETTINGS_VISIBILITY_ALL_SIGNAL_CONNECTIONS_EXCEPT_SUBTITLE_%d",
                    tableName: "PluralAware",
                    comment: "Subtitle for the visibility option. Embeds number of excluded members",
                )
                detailText = String.localizedStringWithFormat(formatString, myStoryThreadRecipientIds.count)
            } else {
                detailText = nil
            }
            visibilitySection.add(buildVisibilityItem(
                title: OWSLocalizedString(
                    "MY_STORIES_SETTINGS_VISIBILITY_ALL_SIGNAL_CONNECTIONS_EXCEPT_TITLE",
                    comment: "Title for the visibility option",
                ),
                detailText: detailText,
                isSelected: isSelected,
                accessory: .none,
            ) { [unowned self] in
                let databaseStorage = SSKEnvironment.shared.databaseStorageRef
                let viewController = databaseStorage.read { tx in
                    return SelectMyStoryRecipientsViewController.load(
                        for: myStoryThread,
                        mode: .blockList,
                        tx: tx,
                        completionBlock: { [weak self] in self?.delegate?.reloadTableContents() },
                    )
                }
                self.delegate?.presentFormSheet(OWSNavigationController(rootViewController: viewController), animated: true)
            })
        }

        do {
            let isSelected = storyViewMode == .explicit
            let detailText: String?
            if isSelected {
                let formatString = OWSLocalizedString(
                    "MY_STORIES_SETTINGS_VISIBILITY_ONLY_SHARE_WITH_SUBTITLE_%d",
                    tableName: "PluralAware",
                    comment: "Subtitle for the visibility option. Embeds number of allowed members",
                )
                detailText = String.localizedStringWithFormat(formatString, myStoryThreadRecipientIds.count)
            } else {
                detailText = nil
            }
            visibilitySection.add(buildVisibilityItem(
                title: OWSLocalizedString(
                    "MY_STORIES_SETTINGS_VISIBILITY_ONLY_SHARE_WITH_TITLE",
                    comment: "Title for the visibility option",
                ),
                detailText: detailText,
                isSelected: isSelected,
                accessory: .none,
            ) { [unowned self] in
                let databaseStorage = SSKEnvironment.shared.databaseStorageRef
                let viewController = databaseStorage.read { tx in
                    return SelectMyStoryRecipientsViewController.load(
                        for: myStoryThread,
                        mode: .explicit,
                        tx: tx,
                        completionBlock: { [weak self] in self?.delegate?.reloadTableContents() },
                    )
                }
                self.delegate?.presentFormSheet(OWSNavigationController(rootViewController: viewController), animated: true)
            })
        }

        switch style {
        case .sheet:
            break
        case .fullscreen:
            let repliesSection = OWSTableSection()
            repliesSection.headerTitle = StoryStrings.repliesAndReactionsHeader
            repliesSection.footerTitle = StoryStrings.repliesAndReactionsFooter
            contents.add(repliesSection)

            repliesSection.add(.switch(
                withText: StoryStrings.repliesAndReactionsToggle,
                isOn: { myStoryThread.allowsReplies },
                target: self,
                selector: #selector(didToggleReplies(_:)),
            ))
        }

        return contents
    }

    @objc
    private func didToggleReplies(_ toggle: UISwitch) {
        let myStoryThread: TSPrivateStoryThread! = SSKEnvironment.shared.databaseStorageRef.read { TSPrivateStoryThread.getMyStory(transaction: $0) }
        guard myStoryThread.allowsReplies != toggle.isOn else { return }
        SSKEnvironment.shared.databaseStorageRef.write { transaction in
            myStoryThread.updateWithAllowsReplies(toggle.isOn, updateStorageService: true, transaction: transaction)
        }
    }

    enum Accessory {
        case none
        case disclosure
        case button(title: String, action: () -> Void)
    }

    func buildVisibilityItem(
        title: String,
        detailText: String? = nil,
        isSelected: Bool,
        accessory: Accessory,
        action: @escaping () -> Void,
    ) -> OWSTableItem {
        OWSTableItem {
            let cell = OWSTableItem.newCell()

            let hStack = UIStackView()
            hStack.axis = .horizontal
            hStack.spacing = 9
            cell.contentView.addSubview(hStack)
            hStack.autoPinWidthToSuperviewMargins()
            hStack.autoSetDimension(.height, toSize: 35, relation: .greaterThanOrEqual)
            hStack.autoPinHeightToSuperview(withMargin: 6)

            let selectionIndicator = ListItemSelectionIndicatorView()
            selectionIndicator.isSelected = isSelected
            hStack.addArrangedSubview(selectionIndicator)

            let vStack = UIStackView()
            vStack.axis = .vertical
            hStack.addArrangedSubview(vStack)

            let titleLabel = UILabel()
            titleLabel.text = title
            titleLabel.numberOfLines = 0
            titleLabel.font = .dynamicTypeBodyClamped
            titleLabel.textColor = .Signal.label
            vStack.addArrangedSubview(titleLabel)

            if let detailText = detailText?.nilIfEmpty {
                let detailLabel = UILabel()
                detailLabel.text = detailText
                detailLabel.numberOfLines = 0
                detailLabel.font = .dynamicTypeCaption1Clamped
                detailLabel.textColor = .Signal.secondaryLabel
                vStack.addArrangedSubview(detailLabel)
            }

            switch accessory {
            case .none:
                break
            case .button(let title, let action):
                let button = UIButton(
                    configuration: .plain(),
                    primaryAction: UIAction { _ in
                        action()
                    },
                )
                button.configuration?.title = title
                button.configuration?.attributedTitle?.font = UIFont.dynamicTypeSubheadlineClamped.semibold()
                button.configuration?.contentInsets.trailing = 0
                button.tintColor = .Signal.label
                button.sizeToFit()

                cell.accessoryView = button
            case .disclosure:
                cell.accessoryType = .disclosureIndicator
            }

            return cell
        } actionBlock: { action() }
    }

    private class SheetHeaderView: UIView {

        let titleLabel = UILabel()
        let subtitleView: LinkingTextView
        let doneButton = UIButton(configuration: .plain())

        init(frame: CGRect, dataSource: MyStorySettingsDataSource) {
            subtitleView = dataSource.makeWhoCanViewThisTextView(for: .sheet)

            super.init(frame: frame)

            titleLabel.text = OWSLocalizedString(
                "MY_STORY_SETTINGS_SHEET_TITLE",
                comment: "Title for the my story settings sheet",
            )
            titleLabel.textAlignment = .center
            titleLabel.font = .dynamicTypeHeadline.semibold()
            titleLabel.textColor = .Signal.label
            addSubview(titleLabel)

            addSubview(subtitleView)

            doneButton.tintColor = .Signal.label
            doneButton.configuration?.title = CommonStrings.doneButton
            doneButton.configuration?.attributedTitle?.font = .dynamicTypeHeadline.semibold()
            doneButton.addAction(
                UIAction { _ in
                    dataSource.didTapDoneButton()
                },
                for: .primaryActionTriggered,
            )
            addSubview(doneButton)

            doneButton.autoPinTrailing(toEdgeOf: self, offset: -16)
            doneButton.autoAlignAxis(.horizontal, toSameAxisOf: titleLabel)
            doneButton.setContentHuggingHigh()

            titleLabel.autoHCenterInSuperview()
            titleLabel.autoPinTopToSuperviewMargin()
            titleLabel.autoPinTrailing(toLeadingEdgeOf: doneButton)

            subtitleView.autoHCenterInSuperview()
            subtitleView.autoPinWidthToSuperview(withMargin: 24)
            subtitleView.autoPinBottomToSuperviewMargin(withInset: 16)
            subtitleView.autoPinEdge(.top, to: .bottom, of: titleLabel, withOffset: 24)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            return nil
        }
    }

    private func makeWhoCanViewThisTextView(for style: Style) -> LinkingTextView {
        let textView = LinkingTextView()

        let baseString: String
        let textAlignment: NSTextAlignment
        switch style {
        case .fullscreen:
            textAlignment = .natural
            baseString = OWSLocalizedString(
                "STORY_SETTINGS_WHO_CAN_VIEW_THIS_FOOTER",
                comment: "Section footer for the 'viewers' section on the 'story settings' view",
            )
        case .sheet:
            textAlignment = .center
            baseString = OWSLocalizedString(
                "STORY_SETTINGS_WHO_CAN_VIEW_THIS_SHEET_HEADER",
                comment: "Header for the 'viewers' section on the 'story settings' bottom sheet",
            )
        }

        // Link doesn't matter, we will override tap behavior.
        let learnMoreString = CommonStrings.learnMore.styled(with: .link(URL(string: Constants.learnMoreUrl)!))
        textView.attributedText = NSAttributedString.composed(of: [
            baseString,
            "\n",
            learnMoreString,
        ]).styled(
            with: .font(.dynamicTypeCaption1Clamped),
            .color(.Signal.secondaryLabel),
            .alignment(textAlignment),
        )
        textView.linkTextAttributes = [.foregroundColor: UIColor.Signal.label]

        textView.delegate = self

        return textView
    }

    private func didTapDoneButton() {
        delegate?.dismiss(animated: true)
    }

    private enum Constants {
        // Link doesn't matter, we will override tap behavior.
        static let learnMoreUrl = "https://support.signal.org/"
    }
}

extension MyStorySettingsDataSource: UITextViewDelegate {

    func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
        guard URL.absoluteString == Constants.learnMoreUrl else {
            return false
        }
        delegate?.present(ConnectionsEducationSheetViewController(), animated: true)
        return false
    }
}
