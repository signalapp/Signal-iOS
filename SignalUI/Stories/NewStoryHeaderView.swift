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

        // TODO: Replace with ContextMenuButton
        let newStoryButton = UIButton(
            configuration: .bordered(),
            primaryAction: UIAction { [weak self] _ in
                self?.didTapNewStory()
            },
        )
        newStoryButton.configuration?.image = UIImage(imageLiteralResourceName: "plus-extra-small")
        newStoryButton.configuration?.imagePlacement = .leading
        newStoryButton.configuration?.imagePadding = 6
        newStoryButton.configuration?.title = OWSLocalizedString(
            "NEW_STORY_HEADER_VIEW_ADD_NEW_STORY_BUTTON",
            comment: "table section header button to add a new story",
        )
        newStoryButton.configuration?.titleTextAttributesTransformer = .defaultFont(.dynamicTypeFootnoteClamped.semibold())
        newStoryButton.configuration?.contentInsets = .init(hMargin: 12, vMargin: 6)
        newStoryButton.configuration?.baseForegroundColor = .Signal.label
        newStoryButton.configuration?.baseBackgroundColor = delegate.cellBackgroundColor
        newStoryButton.configuration?.cornerStyle = .capsule
        addArrangedSubview(newStoryButton)
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func didTapNewStory() {
        let vc = NewStorySheet { [weak self] items in
            guard let self else { return }
            self.delegate.newStoryHeaderView(self, didCreateNewStoryItems: items)
        }
        delegate.present(vc, animated: true)
    }
}
