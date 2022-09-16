//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation

public protocol NewStoryHeaderDelegate: OWSTableViewController2 {
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
            left: OWSTableViewController2.cellHInnerMargin * 0.5,
            bottom: 10,
            right: OWSTableViewController2.cellHInnerMargin * 0.5
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
            font: UIFont.ows_dynamicTypeSubheadlineClamped,
            titleColor: Theme.isDarkThemeEnabled ? UIColor.ows_gray05 : UIColor.ows_gray90,
            backgroundColor: .clear,
            target: self,
            selector: #selector(didTapNewStory)
        )
        newStoryButton.setImage(#imageLiteral(resourceName: "plus-16").withRenderingMode(.alwaysTemplate))
        newStoryButton.contentEdgeInsets = UIEdgeInsets(top: 0, leading: 6, bottom: 0, trailing: 12)
        newStoryButton.titleEdgeInsets = UIEdgeInsets(top: 0, leading: 6, bottom: 0, trailing: -6)
        newStoryButton.tintColor = Theme.primaryIconColor

        addArrangedSubview(newStoryButton)
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
