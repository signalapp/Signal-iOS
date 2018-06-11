//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
class ConversationSearchViewController: UITableViewController {

    var searchResultSet: SearchResultSet = SearchResultSet.empty

    var uiDatabaseConnection: YapDatabaseConnection {
        // TODO do we want to respond to YapDBModified? Might be hard when there's lots of search results, for only marginal value
        return OWSPrimaryStorage.shared().uiDatabaseConnection
    }

    var searcher: ConversationSearcher {
        return ConversationSearcher.shared
    }

    enum SearchSection: Int {
        case conversations = 0
        case contacts = 1
        case messages = 2
    }

    // MARK: View Lifecyle

    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.rowHeight = UITableViewAutomaticDimension
        tableView.estimatedRowHeight = 60

        tableView.register(ChatSearchResultCell.self, forCellReuseIdentifier: ChatSearchResultCell.reuseIdentifier)
        tableView.register(MessageSearchResultCell.self, forCellReuseIdentifier: MessageSearchResultCell.reuseIdentifier)
    }

    // MARK: UITableViewDataSource

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let searchSection = SearchSection(rawValue: section) else {
            owsFail("unknown section: \(section)")
            return 0
        }

        switch searchSection {
        case .conversations:
            return searchResultSet.conversations.count
        case .contacts:
            return searchResultSet.contacts.count
        case .messages:
            return searchResultSet.messages.count
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {

        guard let searchSection = SearchSection(rawValue: indexPath.section) else {
            return UITableViewCell()
        }

        switch searchSection {
        case .conversations:
            guard let cell = tableView.dequeueReusableCell(withIdentifier: ChatSearchResultCell.reuseIdentifier) as? ChatSearchResultCell else {
                return UITableViewCell()
            }

            guard let searchResult = self.searchResultSet.conversations[safe: indexPath.row] else {
                return UITableViewCell()
            }
            cell.configure(searchResult: searchResult)
            return cell
        case .contacts:
            // TODO
            return UITableViewCell()
        case .messages:
            guard let cell = tableView.dequeueReusableCell(withIdentifier: MessageSearchResultCell.reuseIdentifier) as? MessageSearchResultCell else {
                return UITableViewCell()
            }

            guard let searchResult = self.searchResultSet.messages[safe: indexPath.row] else {
                return UITableViewCell()
            }

            cell.configure(searchResult: searchResult)
            return cell
        }
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 3
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let searchSection = SearchSection(rawValue: section) else {
            owsFail("unknown section: \(section)")
            return nil
        }

        switch searchSection {
        case .conversations:
            if searchResultSet.conversations.count > 0 {
                return NSLocalizedString("SEARCH_SECTION_CONVERSATIONS", comment: "section header for search results that match existing conversations (either group or contact conversations)")
            } else {
                return nil
            }
        case .contacts:
            if searchResultSet.contacts.count > 0 {
                return NSLocalizedString("SEARCH_SECTION_CONTACTS", comment: "section header for search results that match a contact who doesn't have an existing conversation")
            } else {
                return nil
            }
        case .messages:
            if searchResultSet.messages.count > 0 {
                return NSLocalizedString("SEARCH_SECTION_MESSAGES", comment: "section header for search results that match a message in a conversation")
            } else {
                return nil
            }
        }
    }

    // MARK: UISearchBarDelegate

    @objc
    public func updateSearchResults(searchText: String) {
        guard searchText.stripped.count > 0 else {
            self.searchResultSet = SearchResultSet.empty
            return
        }

        // TODO: async?
        // TODO: debounce?

        self.uiDatabaseConnection.read { transaction in
            self.searchResultSet = self.searcher.results(searchText: searchText, transaction: transaction)
        }

        // TODO: more perfomant way to do this?
        self.tableView.reloadData()
    }
}

class ChatSearchResultCell: UITableViewCell {
    static let reuseIdentifier = "ChatSearchResultCell"

    let nameLabel: UILabel
    let snippetLabel: UILabel
    let avatarView: AvatarImageView
    let avatarWidth: UInt = 40

    override init(style: UITableViewCellStyle, reuseIdentifier: String?) {
        self.nameLabel = UILabel()
        self.snippetLabel = UILabel()
        self.avatarView = AvatarImageView()
        avatarView.autoSetDimensions(to: CGSize(width: CGFloat(avatarWidth), height: CGFloat(avatarWidth)))

        super.init(style: style, reuseIdentifier: reuseIdentifier)

        nameLabel.font = UIFont.ows_dynamicTypeBody.ows_mediumWeight()
        snippetLabel.font = UIFont.ows_dynamicTypeFootnote

        let textRows = UIStackView(arrangedSubviews: [nameLabel, snippetLabel])
        textRows.axis = .vertical

        let columns = UIStackView(arrangedSubviews: [avatarView, textRows])
        columns.axis = .horizontal
        columns.spacing = 8

        contentView.addSubview(columns)
        columns.autoPinEdgesToSuperviewMargins()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var contactsManager: OWSContactsManager {
        return Environment.current().contactsManager
    }

    func configure(searchResult: SearchResult) {
        self.avatarView.image = OWSAvatarBuilder.buildImage(thread: searchResult.thread.threadRecord, diameter: avatarWidth, contactsManager: self.contactsManager)
        self.nameLabel.text = searchResult.thread.name
        self.snippetLabel.text = searchResult.snippet
    }
}

class MessageSearchResultCell: UITableViewCell {
    static let reuseIdentifier = "MessageSearchResultCell"

    let nameLabel: UILabel
    let snippetLabel: UILabel

    override init(style: UITableViewCellStyle, reuseIdentifier: String?) {
        self.nameLabel = UILabel()
        self.snippetLabel = UILabel()

        super.init(style: style, reuseIdentifier: reuseIdentifier)

        nameLabel.font = UIFont.ows_dynamicTypeBody.ows_mediumWeight()
        snippetLabel.font = UIFont.ows_dynamicTypeFootnote

        let textRows = UIStackView(arrangedSubviews: [nameLabel, snippetLabel])
        textRows.axis = .vertical

        contentView.addSubview(textRows)
        textRows.autoPinEdgesToSuperviewMargins()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(searchResult: SearchResult) {
        self.nameLabel.text = searchResult.thread.name

        guard let snippet = searchResult.snippet else {
            self.snippetLabel.text = nil
            return
        }

        guard let encodedString = snippet.data(using: .utf8) else {
            self.snippetLabel.text = nil
            return
        }

        // Bold snippet text
        do {

            // FIXME - The snippet marks up the matched search text with <b> tags.
            // We can parse this into an attributed string, but it also takes on an undesirable font.
            // We want to apply our own font without clobbering bold in the process - maybe by enumerating and inspecting the attributes? Or maybe we can pass in a base font?
            let attributedSnippet = try NSMutableAttributedString(data: encodedString,
                                                                  options: [NSAttributedString.DocumentReadingOptionKey.documentType: NSAttributedString.DocumentType.html],
                                                                  documentAttributes: nil)
            attributedSnippet.addAttribute(NSAttributedStringKey.font, value: self.snippetLabel.font, range: NSRange(location: 0, length: attributedSnippet.length))

            self.snippetLabel.attributedText = attributedSnippet
        } catch {
            owsFail("failed to generate snippet: \(error)")
        }
    }
}
