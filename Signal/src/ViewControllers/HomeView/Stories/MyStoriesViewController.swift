//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit
import UIKit
import SignalUI

class MyStoriesViewController: OWSTableViewController2 {
    private lazy var emptyStateLabel: UILabel = {
        let label = UILabel()
        label.textColor = Theme.secondaryTextAndIconColor
        label.font = .ows_dynamicTypeBody
        label.numberOfLines = 0
        label.textAlignment = .center
        label.text = NSLocalizedString("MY_STORIES_NO_STORIES", comment: "Indicates that there are no sent stories to render")
        label.isHidden = true
        label.isUserInteractionEnabled = false
        tableView.backgroundView = label
        return label
    }()

    override init() {
        super.init()
        hidesBottomBarWhenPushed = true
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("MY_STORIES_TITLE", comment: "Title for the 'My Stories' view")

        updateTableContents()

        navigationItem.rightBarButtonItem = .init(
            title: NSLocalizedString("STORY_PRIVACY_SETTINGS", comment: "Button to access the story privacy settings menu"),
            style: .plain,
            target: self,
            action: #selector(showPrivacySettings)
        )
    }

    @objc
    func showPrivacySettings() {
        let vc = StoryPrivacySettingsViewController()
        presentFormSheet(OWSNavigationController(rootViewController: vc), animated: true)
    }

    override var tableBackgroundColor: UIColor { Theme.backgroundColor }

    func updateTableContents() {
        let contents = OWSTableContents()
        defer { self.contents = contents }

        let outgoingStories = databaseStorage.read { transaction in
            StoryFinder.outgoingStories(transaction: transaction)
                .compactMap { OutgoingStoryItem(message: $0, transaction: transaction) }
        }

        emptyStateLabel.isHidden = !outgoingStories.isEmpty

        let groupedStories = Dictionary(grouping: outgoingStories) { $0.thread }.sorted { lhs, rhs in
            if (lhs.key as? TSPrivateStoryThread)?.isMyStory == true { return true }
            if (rhs.key as? TSPrivateStoryThread)?.isMyStory == true { return false }
            return (lhs.key.lastSentStoryTimestamp?.uint64Value ?? 0) > (rhs.key.lastSentStoryTimestamp?.uint64Value ?? 0)
        }

        for (thread, stories) in groupedStories {
            let section = OWSTableSection()
            if let groupThread = thread as? TSGroupThread {
                section.headerTitle = groupThread.groupNameOrDefault
            } else if let story = thread as? TSPrivateStoryThread {
                section.headerTitle = story.name
            } else {
                owsFailDebug("Unexpected thread type \(type(of: thread))")
            }

            section.hasSeparators = false
            section.hasBackground = false
            contents.addSection(section)

            for story in stories {
                section.add(.init(customCellBlock: {
                    let cell = OWSTableItem.newCell()

                    let hStackView = UIStackView()
                    hStackView.axis = .horizontal
                    hStackView.alignment = .center
                    hStackView.layoutMargins = UIEdgeInsets(hMargin: Self.defaultHOuterMargin, vMargin: Self.cellVInnerMargin)
                    hStackView.isLayoutMarginsRelativeArrangement = true
                    cell.contentView.addSubview(hStackView)
                    hStackView.autoPinEdgesToSuperviewEdges()

                    let thumbnailView = UIImageView()
                    thumbnailView.autoSetDimensions(to: CGSize(width: 56, height: 84))
                    thumbnailView.contentMode = .scaleAspectFill
                    thumbnailView.clipsToBounds = true
                    thumbnailView.layer.cornerRadius = 12
                    thumbnailView.backgroundColor = Theme.washColor
                    hStackView.addArrangedSubview(thumbnailView)

                    // TODO: Non-image attachments
                    if let attachmentStream = story.fileAttachment as? TSAttachmentStream {
                        thumbnailView.image = attachmentStream.thumbnailImageSmallSync()
                    }

                    hStackView.addArrangedSubview(.spacer(withWidth: 16))

                    let vStackView = UIStackView()
                    vStackView.axis = .vertical
                    vStackView.alignment = .leading
                    hStackView.addArrangedSubview(vStackView)

                    let viewsLabel = UILabel()
                    viewsLabel.font = .ows_dynamicTypeHeadline
                    viewsLabel.textColor = Theme.primaryTextColor
                    let format = NSLocalizedString(
                        "STORY_VIEWS_%d", tableName: "PluralAware",
                        comment: "Text explaining how many views a story has. Embeds {{ %d number of views }}"
                    )
                    viewsLabel.text = String(format: format, story.message.remoteViewCount)
                    vStackView.addArrangedSubview(viewsLabel)

                    let timestampLabel = UILabel()
                    timestampLabel.font = .ows_dynamicTypeSubheadline
                    timestampLabel.textColor = Theme.secondaryTextAndIconColor
                    timestampLabel.text = DateUtil.formatTimestampRelatively(story.message.timestamp)
                    vStackView.addArrangedSubview(timestampLabel)

                    hStackView.addArrangedSubview(.hStretchingSpacer())

                    // TODO: Additional action buttons

                    return cell
                }, actionBlock: {
                    // TODO:
                }))
            }
        }
    }
}

private struct OutgoingStoryItem {
    let message: StoryMessage
    let fileAttachment: TSAttachment?
    let thread: TSThread

    init?(message: StoryMessage, transaction: SDSAnyReadTransaction) {
        self.message = message

        guard case .outgoing(let threadId, _) = message.manifest else {
            owsFailDebug("Unexpected story manifest")
            return nil
        }

        if case .file(let attachmentId) = message.attachment {
            fileAttachment = TSAttachment.anyFetch(uniqueId: attachmentId, transaction: transaction)
        } else {
            fileAttachment = nil
        }

        guard let thread = TSThread.anyFetch(uniqueId: threadId, transaction: transaction) else {
            owsFailDebug("Unexpectedly missing thread for story")
            return nil
        }
        self.thread = thread
    }
}
