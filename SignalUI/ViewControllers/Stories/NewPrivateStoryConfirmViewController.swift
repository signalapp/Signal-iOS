//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SafariServices
import SignalServiceKit

@objc
public class NewPrivateStoryConfirmViewController: OWSTableViewController2 {

    let recipientSet: OrderedSet<PickedRecipient>
    let selectItemsInParent: (([StoryConversationItem]) -> Void)?
    var allowsReplies = true

    required init(recipientSet: OrderedSet<PickedRecipient>, selectItemsInParent: (([StoryConversationItem]) -> Void)? = nil) {
        self.recipientSet = recipientSet
        self.selectItemsInParent = selectItemsInParent

        super.init()

        self.shouldAvoidKeyboard = true
    }

    // MARK: - View Lifecycle

    @objc
    public override func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString(
            "NEW_PRIVATE_STORY_CONFIRM_TITLE",
            comment: "Title for the 'new private story' confirmation view"
        )

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: OWSLocalizedString(
                "NEW_PRIVATE_STORY_CREATE_BUTTON",
                comment: "Button to create a new private story"
            ),
            style: .plain,
            target: self,
            action: #selector(didTapCreate)
        )

        tableView.register(ContactTableViewCell.self, forCellReuseIdentifier: ContactTableViewCell.reuseIdentifier)

        updateTableContents()
    }

    private var lastViewSize = CGSize.zero
    public override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()

        guard view.frame.size != lastViewSize else { return }
        lastViewSize = view.frame.size
        updateTableContents()
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        nameTextField.becomeFirstResponder()
    }

    // MARK: -

    private lazy var nameTextField: UITextField = {
        let textField = UITextField()

        textField.font = .ows_dynamicTypeBody
        textField.backgroundColor = .clear
        textField.placeholder = OWSLocalizedString(
            "NEW_PRIVATE_STORY_NAME_PLACEHOLDER",
            comment: "Placeholder text for a new private story name"
        )

        return textField
    }()
    private lazy var iconImageView: UIImageView = {
        let imageView = UIImageView()

        imageView.contentMode = .center
        imageView.layer.cornerRadius = 32
        imageView.clipsToBounds = true
        imageView.autoSetDimensions(to: CGSize(square: 64))

        return imageView
    }()

    public override func applyTheme() {
        super.applyTheme()

        nameTextField.textColor = Theme.primaryTextColor

        iconImageView.setThemeIcon(.privateStory40, tintColor: Theme.primaryIconColor)
        iconImageView.backgroundColor = Theme.isDarkThemeEnabled ? .ows_gray65 : .ows_gray02
    }

    private func updateTableContents() {
        let contents = OWSTableContents()

        let nameAndAvatarSection = OWSTableSection()
        nameAndAvatarSection.add(.init(
            customCellBlock: { [weak self] in
                let cell = OWSTableItem.newCell()
                cell.selectionStyle = .none
                guard let self = self else { return cell }

                self.iconImageView.setContentHuggingVerticalHigh()
                self.nameTextField.setContentHuggingHorizontalLow()
                let firstSection = UIStackView(arrangedSubviews: [
                    self.iconImageView,
                    self.nameTextField
                ])
                firstSection.axis = .horizontal
                firstSection.alignment = .center
                firstSection.spacing = ContactCellView.avatarTextHSpacing

                cell.contentView.addSubview(firstSection)
                firstSection.autoPinEdgesToSuperviewMargins()

                return cell
            },
            actionBlock: {}
        ))
        contents.addSection(nameAndAvatarSection)

        let repliesSection = OWSTableSection()
        repliesSection.headerTitle = StoryStrings.repliesAndReactionsHeader
        repliesSection.footerTitle = StoryStrings.repliesAndReactionsFooter
        contents.addSection(repliesSection)

        repliesSection.add(.switch(
            withText: StoryStrings.repliesAndReactionsToggle,
            isOn: { [allowsReplies] in allowsReplies },
            target: self,
            selector: #selector(didToggleReplies)
        ))

        let viewerAddresses = databaseStorage.read { transaction in
            BaseMemberViewController.orderedMembers(
                recipientSet: self.recipientSet,
                shouldSort: true,
                transaction: transaction
            )
        }.compactMap { $0.address }

        let viewersSection = OWSTableSection()
        viewersSection.headerTitle = OWSLocalizedString(
            "NEW_PRIVATE_STORY_VIEWERS_HEADER",
            comment: "Header for the 'viewers' section of the 'new private story' view"
        )

        for address in viewerAddresses {
            viewersSection.add(OWSTableItem(
                dequeueCellBlock: { tableView in
                    guard let cell = tableView.dequeueReusableCell(withIdentifier: ContactTableViewCell.reuseIdentifier) as? ContactTableViewCell else {
                        owsFailDebug("Missing cell.")
                        return UITableViewCell()
                    }

                    cell.selectionStyle = .none

                    Self.databaseStorage.read { transaction in
                        let configuration = ContactCellConfiguration(address: address, localUserDisplayMode: .asUser)
                        cell.configure(configuration: configuration, transaction: transaction)
                    }
                    return cell
                }))
        }
        contents.addSection(viewersSection)

        self.contents = contents
    }

    // MARK: - Actions

    @objc
    func didTapCreate() {
        AssertIsOnMainThread()

        guard let name = nameTextField.text?.filterForDisplay?.nilIfEmpty else {
            return showMissingNameAlert()
        }

        let newStory = TSPrivateStoryThread(
            name: name,
            allowsReplies: allowsReplies,
            addresses: recipientSet.orderedMembers.compactMap { $0.address },
            viewMode: .explicit
        )
        databaseStorage.asyncWrite { transaction in
            newStory.anyInsert(transaction: transaction)

            if let dlistId = newStory.distributionListIdentifier {
                Self.storageServiceManager.recordPendingUpdates(updatedStoryDistributionListIds: [dlistId])
            }
        } completion: { [weak self] in
            guard let self = self else { return }
            self.dismiss(animated: true)
            self.selectItemsInParent?(
                [StoryConversationItem(
                    backingItem: .privateStory(.init(
                        storyThreadId: newStory.uniqueId,
                        isMyStory: false
                    ))
                )]
            )
        }
    }

    @objc
    func didToggleReplies() {
        allowsReplies = !allowsReplies
    }

    public func showMissingNameAlert() {
        AssertIsOnMainThread()

        OWSActionSheets.showActionSheet(
            title: OWSLocalizedString(
                "NEW_PRIVATE_STORY_MISSING_NAME_ALERT_TITLE",
                comment: "Title for error alert indicating that a story name is required."
            ),
            message: OWSLocalizedString(
                "NEW_PRIVATE_STORY_MISSING_NAME_ALERT_MESSAGE",
                comment: "Message for error alert indicating that a story name is required."
            )
        )
    }
}
