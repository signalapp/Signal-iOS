//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

public protocol NewStoryHeaderDelegate: AnyObject, OWSTableViewController2 {
    func newStoryHeaderView(_ newStoryHeaderView: NewStoryHeaderView, didCreateNewStoryItems items: [StoryConversationItem])
}

public class NewStoryHeaderView: UIStackView {
    weak var delegate: NewStoryHeaderDelegate!

    public init(
        title: String,
        showsNewStoryButton: Bool = true,
        delegate: NewStoryHeaderDelegate,
    ) {
        self.delegate = delegate

        super.init(frame: .zero)

        axis = .horizontal
        isLayoutMarginsRelativeArrangement = true
        layoutMargins = .init(
            top: 11,
            leading: OWSTableViewController2.cellHInnerMargin * 0.5,
            bottom: 14,
            trailing: 0,
        )
        layoutMargins.left += delegate.tableView.safeAreaInsets.left
        layoutMargins.right += delegate.tableView.safeAreaInsets.right

        let textView = UILabel()
        textView.textColor = UIColor.Signal.label
        textView.font = UIFont.dynamicTypeHeadlineClamped
        textView.text = title

        addArrangedSubview(textView)
        addArrangedSubview(.hStretchingSpacer())

        var configuration = UIButton.Configuration.bordered()
        configuration.image = UIImage(imageLiteralResourceName: "plus-extra-small")
        configuration.imagePlacement = .leading
        configuration.imagePadding = 6
        configuration.title = OWSLocalizedString(
            "NEW_STORY_HEADER_VIEW_ADD_NEW_STORY_BUTTON",
            comment: "table section header button to add a new story",
        )
        configuration.titleTextAttributesTransformer = .defaultFont(.dynamicTypeFootnoteClamped.semibold())
        configuration.contentInsets = .init(hMargin: 12, vMargin: 6)
        configuration.baseForegroundColor = .Signal.label
        configuration.baseBackgroundColor = delegate.cellBackgroundColor
        configuration.cornerStyle = .capsule
        let newStoryButton = UIButton(configuration: configuration)
        newStoryButton.showsMenuAsPrimaryAction = true
        newStoryButton.menu = UIMenu(children: [
            UIAction(
                title: OWSLocalizedString(
                    "NEW_STORY_SHEET_CUSTOM_STORY_TITLE",
                    comment: "Title for create custom story row on the 'new story sheet'",
                ),
                subtitle: OWSLocalizedString(
                    "NEW_STORY_SHEET_CUSTOM_STORY_SUBTITLE",
                    comment: "Subtitle for create custom story row on the 'new story sheet'",
                ),
                image: Theme.iconImage(.genericStories),
                handler: { [weak self] _ in
                    self?.didTapNewCustomStory()
                },
            ),
            UIAction(
                title: OWSLocalizedString(
                    "NEW_STORY_SHEET_GROUP_STORY_TITLE",
                    comment: "Title for create group story row on the 'new story sheet'",
                ),
                subtitle: OWSLocalizedString(
                    "NEW_STORY_SHEET_GROUP_STORY_SUBTITLE",
                    comment: "Subtitle for create group story row on the 'new story sheet'",
                ),
                image: Theme.iconImage(.genericGroup),
                handler: { [weak self] _ in
                    self?.didTapNewGroupStory()
                },
            ),
        ])
        addArrangedSubview(newStoryButton)
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func didTapNewCustomStory() {
        let vc = NewPrivateStoryRecipientsViewController { [weak self] items in
            guard let self else { return }
            self.delegate.newStoryHeaderView(self, didCreateNewStoryItems: items)
        }
        delegate.presentFormSheet(OWSNavigationController(rootViewController: vc), animated: true)
    }

    private func didTapNewGroupStory() {
        let vc = NewGroupStoryViewController { [weak self] items in
            guard let self else { return }
            self.delegate.newStoryHeaderView(self, didCreateNewStoryItems: items)
        }
        delegate.presentFormSheet(OWSNavigationController(rootViewController: vc), animated: true)

    }
}
