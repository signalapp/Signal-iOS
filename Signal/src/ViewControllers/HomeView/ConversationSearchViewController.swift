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

        self.view.isHidden = true

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

    /*
    @available(iOS 2.0, *)
    optional public func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String?
    
    
    // Editing
    
    // Individual rows can opt out of having the -editing property set for them. If not implemented, all rows are assumed to be editable.
    @available(iOS 2.0, *)
    optional public func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool
    
    
    // Moving/reordering
    
    // Allows the reorder accessory view to optionally be shown for a particular row. By default, the reorder control will be shown only if the datasource implements -tableView:moveRowAtIndexPath:toIndexPath:
    @available(iOS 2.0, *)
    optional public func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool
    
    
    // Index
    
    @available(iOS 2.0, *)
    optional public func sectionIndexTitles(for tableView: UITableView) -> [String]? // return list of section titles to display in section index view (e.g. "ABCD...Z#")
    
    @available(iOS 2.0, *)
    optional public func tableView(_ tableView: UITableView, sectionForSectionIndexTitle title: String, at index: Int) -> Int // tell table which section corresponds to section title/index (e.g. "B",1))
    
    
    // Data manipulation - insert and delete support
    
    // After a row has the minus or plus button invoked (based on the UITableViewCellEditingStyle for the cell), the dataSource must commit the change
    // Not called for edit actions using UITableViewRowAction - the action's handler will be invoked instead
    @available(iOS 2.0, *)
    optional public func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCellEditingStyle, forRowAt indexPath: IndexPath)
    
    
    // Data manipulation - reorder / moving support
    
    @available(iOS 2.0, *)
    optional public func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath)
 
     */

}

extension ConversationSearchViewController: UISearchBarDelegate {
    public func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        guard searchText.stripped.count > 0 else {
            self.searchResultSet = SearchResultSet.empty
            self.view.isHidden = true
            return
        }

        self.view.isHidden = false

        self.uiDatabaseConnection.read { transaction in
            self.searchResultSet = self.searcher.results(searchText: searchText, transaction: transaction)
        }

        // TODO: debounce
        // TODO: more perfomant way to do this?
        self.tableView.reloadData()
    }
}

class ChatSearchResultCell: UITableViewCell {
    static let reuseIdentifier = "ChatSearchResultCell"

    let nameLabel: UILabel
    let snippetLabel: UILabel
    let avatarView: AvatarImageView

    override init(style: UITableViewCellStyle, reuseIdentifier: String?) {
        self.nameLabel = UILabel()
        self.snippetLabel = UILabel()
        self.avatarView = AvatarImageView()
        avatarView.autoSetDimensions(to: CGSize(width: 40, height: 40))

        super.init(style: style, reuseIdentifier: reuseIdentifier)

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

    func configure(searchResult: SearchResult) {
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
            let attributedSnippet = try NSAttributedString(data: encodedString,
                                                           options: [NSAttributedString.DocumentReadingOptionKey.documentType: NSAttributedString.DocumentType.html],
                                                           documentAttributes: nil)

            self.snippetLabel.attributedText = attributedSnippet
        } catch {
            owsFail("failed to generate snippet: \(error)")
        }
    }
}
