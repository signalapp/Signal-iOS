//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import UIKit
import SignalMessaging

public class MyStorySettingsViewController: OWSTableViewController2, MyStorySettingsDataSourceDelegate {

    private lazy var dataSource = MyStorySettingsDataSource(delegate: self)

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        // Mark the my story privacy setting as having been set if the user
        // views this screen at all.
        Self.databaseStorage.write {
            StoryManager.setHasSetMyStoriesPrivacy(transaction: $0)
        }
    }

    public override func viewDidLoad() {
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

    public init(willDisappear: (() -> Void)?) {
        self.willDisappear = willDisappear
        super.init()
    }

    public required init() {
        super.init()
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        // Mark the my story privacy setting as having been set if the user
        // views this screen at all.
        Self.databaseStorage.write {
            StoryManager.setHasSetMyStoriesPrivacy(transaction: $0)
        }
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        willDisappear?()
    }

    public override func updateTableContents(shouldReload: Bool = true) {
        let contents = dataSource.generateTableContents(style: .sheet)
        self.tableViewController.setContents(contents, shouldReload: shouldReload)
    }

    func reloadTableContents() {
        self.updateTableContents(shouldReload: true)
    }
}

private protocol MyStorySettingsDataSourceDelegate: UIViewController {
    func reloadTableContents()
}

private class MyStorySettingsDataSource: Dependencies {

    private weak var delegate: MyStorySettingsDataSourceDelegate?

    init(delegate: MyStorySettingsDataSourceDelegate) {
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

        let myStoryThread: TSPrivateStoryThread! = databaseStorage.read {
            TSPrivateStoryThread.getMyStory(transaction: $0)
        }

        let visibilitySection = OWSTableSection()
        visibilitySection.separatorInsetLeading = NSNumber(value: OWSTableViewController2.cellHInnerMargin + 32)
        switch style {
        case .sheet:
            visibilitySection.customHeaderView = SheetHeaderView(frame: .zero, dataSource: self)
            break
        case .fullscreen:
            visibilitySection.headerTitle = OWSLocalizedString(
                "STORY_SETTINGS_WHO_CAN_VIEW_THIS_HEADER",
                comment: "Section header for the 'viewers' section on the 'story settings' view"
            )
            // TODO: Add 'learn more' sheet button
            visibilitySection.footerTitle = OWSLocalizedString(
                "STORY_SETTINGS_WHO_CAN_VIEW_THIS_FOOTER",
                comment: "Section footer for the 'viewers' section on the 'story settings' view"
            )
        }
        contents.addSection(visibilitySection)

        do {
            let isSelected = myStoryThread.storyViewMode == .blockList && myStoryThread.addresses.isEmpty
            visibilitySection.add(buildVisibilityItem(
                title: OWSLocalizedString(
                    "MY_STORIES_SETTINGS_VISIBILITY_ALL_SIGNAL_CONNECTIONS_TITLE",
                    comment: "Title for the visibility option"),
                isSelected: isSelected,
                showDisclosureIndicator: false
            ) { [weak self] in
                Self.databaseStorage.write { transaction in
                    myStoryThread.updateWithStoryViewMode(
                        .blockList,
                        addresses: [],
                        updateStorageService: true,
                        transaction: transaction
                    )
                }
                self?.delegate?.reloadTableContents()
            })
        }

        do {
            let isSelected = myStoryThread.storyViewMode == .blockList && myStoryThread.addresses.count > 0
            let detailText: String?
            if isSelected {
                let formatString = OWSLocalizedString(
                    "MY_STORIES_SETTINGS_VISIBILITY_ALL_SIGNAL_CONNECTIONS_EXCEPT_SUBTITLE_%d",
                    tableName: "PluralAware",
                    comment: "Subtitle for the visibility option. Embeds number of excluded members")
                detailText = String.localizedStringWithFormat(formatString, myStoryThread.addresses.count)
            } else {
                detailText = nil
            }
            visibilitySection.add(buildVisibilityItem(
                title: OWSLocalizedString(
                    "MY_STORIES_SETTINGS_VISIBILITY_ALL_SIGNAL_CONNECTIONS_EXCEPT_TITLE",
                    comment: "Title for the visibility option"),
                detailText: detailText,
                isSelected: isSelected,
                showDisclosureIndicator: true
            ) { [weak self] in
                let vc = SelectMyStoryRecipientsViewController(thread: myStoryThread, mode: .blockList) {
                    self?.delegate?.reloadTableContents()
                }
                self?.delegate?.presentFormSheet(OWSNavigationController(rootViewController: vc), animated: true)
            })
        }

        do {
            let isSelected = myStoryThread.storyViewMode == .explicit
            let detailText: String?
            if isSelected {
                let formatString = OWSLocalizedString(
                    "MY_STORIES_SETTINGS_VISIBILITY_ONLY_SHARE_WITH_SUBTITLE_%d",
                    tableName: "PluralAware",
                    comment: "Subtitle for the visibility option. Embeds number of allowed members")
                detailText = String.localizedStringWithFormat(formatString, myStoryThread.addresses.count)
            } else {
                detailText = nil
            }
            visibilitySection.add(buildVisibilityItem(
                title: OWSLocalizedString(
                    "MY_STORIES_SETTINGS_VISIBILITY_ONLY_SHARE_WITH_TITLE",
                    comment: "Title for the visibility option"),
                detailText: detailText,
                isSelected: isSelected,
                showDisclosureIndicator: true
            ) { [weak self] in
                let vc = SelectMyStoryRecipientsViewController(thread: myStoryThread, mode: .explicit) {
                    self?.delegate?.reloadTableContents()
                }
                self?.delegate?.presentFormSheet(OWSNavigationController(rootViewController: vc), animated: true)
            })
        }

        switch style {
        case .sheet:
            break
        case .fullscreen:
            let repliesSection = OWSTableSection()
            repliesSection.headerTitle = StoryStrings.repliesAndReactionsHeader
            repliesSection.footerTitle = StoryStrings.repliesAndReactionsFooter
            contents.addSection(repliesSection)

            repliesSection.add(.switch(
                withText: StoryStrings.repliesAndReactionsToggle,
                isOn: { myStoryThread.allowsReplies },
                target: self,
                selector: #selector(didToggleReplies(_:))
            ))
        }

        return contents
    }

    @objc
    func didToggleReplies(_ toggle: UISwitch) {
        let myStoryThread: TSPrivateStoryThread! = databaseStorage.read { TSPrivateStoryThread.getMyStory(transaction: $0) }
        guard myStoryThread.allowsReplies != toggle.isOn else { return }
        databaseStorage.write { transaction in
            myStoryThread.updateWithAllowsReplies(toggle.isOn, updateStorageService: true, transaction: transaction)
        }
    }

    func buildVisibilityItem(
        title: String,
        detailText: String? = nil,
        isSelected: Bool,
        showDisclosureIndicator: Bool,
        action: @escaping () -> Void
    ) -> OWSTableItem {
        OWSTableItem {
            let cell = OWSTableItem.newCell()

            let hStack = UIStackView()
            hStack.axis = .horizontal
            hStack.spacing = 9
            cell.contentView.addSubview(hStack)
            hStack.autoPinEdgesToSuperviewMargins()

            if isSelected {
                let imageView = UIImageView()
                imageView.contentMode = .center
                imageView.autoSetDimension(.width, toSize: 22)
                imageView.setThemeIcon(.accessoryCheckmark, tintColor: Theme.primaryIconColor)
                hStack.addArrangedSubview(imageView)
            } else {
                hStack.addArrangedSubview(.spacer(withWidth: 22))
            }

            let titleLabel = UILabel()
            titleLabel.text = title
            titleLabel.numberOfLines = 0
            titleLabel.font = .ows_dynamicTypeBody
            titleLabel.textColor = Theme.primaryTextColor
            hStack.addArrangedSubview(titleLabel)

            if let detailText = detailText {
                let detailLabel = UILabel()
                detailLabel.setContentHuggingHorizontalHigh()
                detailLabel.text = detailText
                detailLabel.numberOfLines = 0
                detailLabel.font = .ows_dynamicTypeBody
                detailLabel.textColor = Theme.secondaryTextAndIconColor
                hStack.addArrangedSubview(detailLabel)
            }

            if showDisclosureIndicator {
                cell.accessoryType = .disclosureIndicator
            }

            return cell
        } actionBlock: { action() }
    }

    private class SheetHeaderView: UIView {

        let titleLabel = UILabel()
        let subtitleLabel = UILabel()
        let doneButton = UIButton()

        init(frame: CGRect, dataSource: MyStorySettingsDataSource) {
            super.init(frame: frame)

            titleLabel.text = OWSLocalizedString(
                "MY_STORY_SETTINGS_SHEET_TITLE",
                comment: "Title for the my story settings sheet"
            )
            titleLabel.textAlignment = .center
            titleLabel.font = .ows_dynamicTypeHeadline.ows_semibold
            titleLabel.textColor = Theme.primaryTextColor
            addSubview(titleLabel)

            // TODO: Add 'learn more' sheet button
            subtitleLabel.text = OWSLocalizedString(
                "STORY_SETTINGS_WHO_CAN_VIEW_THIS_FOOTER",
                comment: "Section footer for the 'viewers' section on the 'story settings' view"
            )
            subtitleLabel.textAlignment = .center
            subtitleLabel.numberOfLines = 0
            subtitleLabel.font = .ows_dynamicTypeFootnote
            subtitleLabel.textColor = Theme.secondaryTextAndIconColor
            addSubview(subtitleLabel)

            doneButton.setTitle(CommonStrings.doneButton, for: .normal)
            doneButton.titleLabel?.font = .ows_dynamicTypeHeadline.ows_semibold
            doneButton.setTitleColor(Theme.primaryTextColor, for: .normal)
            doneButton.addTarget(dataSource, action: #selector(didTapDoneButton), for: .touchUpInside)
            addSubview(doneButton)

            doneButton.autoPinTrailing(toEdgeOf: self, offset: -16)
            doneButton.autoAlignAxis(.horizontal, toSameAxisOf: titleLabel)
            doneButton.setContentHuggingHigh()

            titleLabel.autoHCenterInSuperview()
            titleLabel.autoPinTopToSuperviewMargin()
            titleLabel.autoPinTrailing(toLeadingEdgeOf: doneButton)

            subtitleLabel.autoHCenterInSuperview()
            subtitleLabel.autoPinWidthToSuperview(withMargin: 42)
            subtitleLabel.autoPinBottomToSuperviewMargin(withInset: 16)
            subtitleLabel.autoPinEdge(.top, to: .bottom, of: titleLabel, withOffset: 24)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            return nil
        }
    }

    @objc
    private func didTapDoneButton() {
        delegate?.dismiss(animated: true)
    }
}
