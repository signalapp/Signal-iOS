//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import UIKit
import SignalMessaging
import BonMot

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

private protocol MyStorySettingsDataSourceDelegate: AnyObject, UIViewController {
    func reloadTableContents()
}

private class MyStorySettingsDataSource: NSObject, Dependencies {

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

        let myStoryThread: TSPrivateStoryThread! = databaseStorage.read {
            TSPrivateStoryThread.getMyStory(transaction: $0)
        }

        let visibilitySection = OWSTableSection()
        visibilitySection.separatorInsetLeading = NSNumber(value: OWSTableViewController2.cellHInnerMargin + 32)
        switch style {
        case .sheet:
            visibilitySection.customHeaderView = SheetHeaderView(frame: .zero, dataSource: self)
        case .fullscreen:
            visibilitySection.headerTitle = OWSLocalizedString(
                "STORY_SETTINGS_WHO_CAN_VIEW_THIS_HEADER",
                comment: "Section header for the 'viewers' section on the 'story settings' view"
            )
            let footerTextView = makeWhoCanViewThisTextView(for: style)
            let footerContainer = UIView()
            footerContainer.addSubview(footerTextView)
            footerTextView.autoPinEdgesToSuperviewEdges(withInsets: .init(hMargin: 32, vMargin: 16))
            visibilitySection.customFooterView = footerContainer
        }
        contents.addSection(visibilitySection)

        do {
            let isSelected = myStoryThread.storyViewMode == .blockList && myStoryThread.addresses.isEmpty
            let detailText: String?
            if isSelected {
                let formatString = OWSLocalizedString(
                    "MY_STORIES_SETTINGS_VISIBILITY_ALL_SIGNAL_CONNECTIONS_SUBTITLE_%d",
                    tableName: "PluralAware",
                    comment: "Subtitle for the visibility option. Embeds number of allowed members")
                detailText = String.localizedStringWithFormat(formatString, myStoryThread.recipientAddressesWithSneakyTransaction.count)
            } else {
                detailText = nil
            }
            visibilitySection.add(buildVisibilityItem(
                title: OWSLocalizedString(
                    "MY_STORIES_SETTINGS_VISIBILITY_ALL_SIGNAL_CONNECTIONS_TITLE",
                    comment: "Title for the visibility option"),
                detailText: detailText,
                isSelected: isSelected,
                accessory: isSelected ? .button(title: CommonStrings.viewButton, action: { [weak self] in
                    let vc = AllSignalConnectionsViewController()
                    self?.delegate?.presentFormSheet(OWSNavigationController(rootViewController: vc), animated: true)
                }) : .none
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
                accessory: .none
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
                accessory: .none
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
        action: @escaping () -> Void
    ) -> OWSTableItem {
        OWSTableItem {
            let cell = OWSTableItem.newCell()

            let hStack = UIStackView()
            hStack.axis = .horizontal
            hStack.spacing = 9
            cell.contentView.addSubview(hStack)
            hStack.autoPinWidthToSuperviewMargins()

            if isSelected {
                let imageView = UIImageView()
                imageView.contentMode = .center
                imageView.autoSetDimension(.width, toSize: 22)
                imageView.setThemeIcon(.accessoryCheckmark, tintColor: Theme.primaryIconColor)
                hStack.addArrangedSubview(imageView)
            } else {
                hStack.addArrangedSubview(.spacer(withWidth: 22))
            }

            let vStack = UIStackView()
            vStack.axis = .vertical
            hStack.addArrangedSubview(vStack)

            let titleLabel = UILabel()
            titleLabel.text = title
            titleLabel.numberOfLines = 0
            titleLabel.font = .ows_dynamicTypeBodyClamped
            titleLabel.textColor = Theme.primaryTextColor
            vStack.addArrangedSubview(titleLabel)

            if let detailText = detailText?.nilIfEmpty {
                let detailLabel = UILabel()
                detailLabel.text = detailText
                detailLabel.numberOfLines = 0
                detailLabel.font = .ows_dynamicTypeCaption1Clamped
                detailLabel.textColor = Theme.secondaryTextAndIconColor
                vStack.addArrangedSubview(detailLabel)

                hStack.autoPinHeightToSuperview(withMargin: 6)
            } else {
                hStack.autoPinHeightToSuperviewMargins()
            }

            switch accessory {
            case .none:
                break
            case .button(let title, let action):
                let button = OWSButton(block: action)
                button.setTitle(title, for: .normal)
                button.setTitleColor(Theme.primaryTextColor, for: .normal)
                button.setTitleColor(Theme.primaryTextColor.withAlphaComponent(0.6), for: .highlighted)
                button.titleLabel?.font = .ows_dynamicTypeSubheadlineClamped.ows_semibold
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
        let doneButton = UIButton()

        init(frame: CGRect, dataSource: MyStorySettingsDataSource) {
            subtitleView = dataSource.makeWhoCanViewThisTextView(for: .sheet)

            super.init(frame: frame)

            titleLabel.text = OWSLocalizedString(
                "MY_STORY_SETTINGS_SHEET_TITLE",
                comment: "Title for the my story settings sheet"
            )
            titleLabel.textAlignment = .center
            titleLabel.font = .ows_dynamicTypeHeadline.ows_semibold
            titleLabel.textColor = Theme.primaryTextColor
            addSubview(titleLabel)

            addSubview(subtitleView)

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
                comment: "Section footer for the 'viewers' section on the 'story settings' view"
            )
        case .sheet:
            textAlignment = .center
            baseString = OWSLocalizedString(
                "STORY_SETTINGS_WHO_CAN_VIEW_THIS_SHEET_HEADER",
                comment: "Header for the 'viewers' section on the 'story settings' bottom sheet"
            )
        }

        // Link doesn't matter, we will override tap behavior.
        let learnMoreString = CommonStrings.learnMore.styled(with: .link(URL(string: Constants.learnMoreUrl)!))
        textView.attributedText = NSAttributedString.composed(of: [
            baseString,
            "\n",
            learnMoreString
        ]).styled(
            with: .font(.ows_dynamicTypeCaption1Clamped),
            .color(Theme.secondaryTextAndIconColor),
            .alignment(textAlignment)
        )
        textView.linkTextAttributes = [
            .foregroundColor: Theme.primaryTextColor,
            .underlineColor: UIColor.clear,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]

        textView.delegate = self

        return textView
    }

    @objc
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
        delegate?.present(MyStorySettingsLearnMoreSheetViewController(), animated: true)
        return false
    }
}
