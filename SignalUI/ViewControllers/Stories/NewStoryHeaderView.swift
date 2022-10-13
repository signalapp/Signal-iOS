//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol NewStoryHeaderDelegate: AnyObject, OWSTableViewController2 {
    func newStoryHeaderView(_ newStoryHeaderView: NewStoryHeaderView, didCreateNewStoryItems items: [StoryConversationItem])
}

public class NewStoryHeaderView: UIStackView {
    weak var delegate: NewStoryHeaderDelegate!

    public init(title: String, delegate: NewStoryHeaderDelegate) {
        self.delegate = delegate

        super.init(frame: .zero)

        addBackgroundView(withBackgroundColor: delegate.tableBackgroundColor)
        axis = .horizontal
        isLayoutMarginsRelativeArrangement = true
        layoutMargins = delegate.cellOuterInsetsWithMargin(
            top: (delegate.defaultSpacingBetweenSections ?? 0) + 12,
            left: CurrentAppContext().isRTL ? 0 : OWSTableViewController2.cellHInnerMargin * 0.5,
            bottom: 10,
            right: CurrentAppContext().isRTL ? OWSTableViewController2.cellHInnerMargin * 0.5 : 0
        )
        layoutMargins.left += delegate.tableView.safeAreaInsets.left
        layoutMargins.right += delegate.tableView.safeAreaInsets.right

        let textView = LinkingTextView()
        textView.textColor = Theme.isDarkThemeEnabled ? UIColor.ows_gray05 : UIColor.ows_gray90
        textView.font = UIFont.ows_dynamicTypeBodyClamped.ows_semibold
        textView.text = title

        addArrangedSubview(textView)
        addArrangedSubview(.hStretchingSpacer())

        // TODO: Replace with ContextMenuButton
        let newStoryButton = OWSFlatButton.button(
            title: OWSLocalizedString(
                "NEW_STORY_HEADER_VIEW_ADD_NEW_STORY_BUTTON",
                comment: "table section header button to add a new story"
            ),
            font: UIFont.ows_dynamicTypeFootnoteClamped.ows_semibold,
            titleColor: Theme.isDarkThemeEnabled ? UIColor.ows_gray05 : UIColor.ows_gray90,
            backgroundColor: delegate.cellBackgroundColor,
            target: self,
            selector: #selector(didTapNewStory)
        )
        newStoryButton.setImage(#imageLiteral(resourceName: "plus-12").withRenderingMode(.alwaysTemplate))
        newStoryButton.contentEdgeInsets = UIEdgeInsets(top: 5, leading: 8, bottom: 5, trailing: 9)
        newStoryButton.titleEdgeInsets = UIEdgeInsets(top: 0, leading: 1, bottom: 0, trailing: -1)
        newStoryButton.tintColor = Theme.primaryIconColor
        newStoryButton.clipsToBounds = true

        let pillWrapper = ManualLayoutView(name: "PillWrapper")
        pillWrapper.shouldDeactivateConstraints = false

        pillWrapper.addSubview(newStoryButton) { view in
            newStoryButton.layer.cornerRadius = view.height / 2
        }
        newStoryButton.autoPinEdgesToSuperviewEdges()

        addArrangedSubview(pillWrapper)
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc
    func didTapNewStory() {
        let vc = NewStorySheet { [weak self] items in
            guard let self = self else { return }
            self.delegate.newStoryHeaderView(self, didCreateNewStoryItems: items)
        }
        delegate.present(vc, animated: true)
    }
}
