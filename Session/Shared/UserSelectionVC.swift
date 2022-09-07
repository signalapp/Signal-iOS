// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import SessionUIKit
import SessionMessagingKit

final class UserSelectionVC: BaseVC, UITableViewDataSource, UITableViewDelegate {
    private let navBarTitle: String
    private let usersToExclude: Set<String>
    private let completion: (Set<String>) -> Void
    private var selectedUsers: Set<String> = []

    private lazy var users: [Profile] = {
        return Profile
            .fetchAllContactProfiles(excluding: usersToExclude)
    }()

    // MARK: - Components
    
    @objc private lazy var tableView: UITableView = {
        let result: UITableView = UITableView()
        result.dataSource = self
        result.delegate = self
        result.separatorStyle = .none
        result.themeBackgroundColor = .clear
        result.showsVerticalScrollIndicator = false
        result.alwaysBounceVertical = false
        result.register(view: UserCell.self)
        
        return result
    }()

    // MARK: - Lifecycle
    
    init(with title: String, excluding usersToExclude: Set<String>, completion: @escaping (Set<String>) -> Void) {
        self.navBarTitle = title
        self.usersToExclude = usersToExclude
        self.completion = completion
        
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { preconditionFailure("Use init(excluding:) instead.") }
    override init(nibName: String?, bundle: Bundle?) { preconditionFailure("Use init(excluding:) instead.") }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        setNavBarTitle(navBarTitle)
        
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(handleDoneButtonTapped))
        view.addSubview(tableView)
        tableView.pin(to: view)
    }

    // MARK: - UITableViewDataSource
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return users.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell: UserCell = tableView.dequeue(type: UserCell.self, for: indexPath)
        cell.update(
            with: users[indexPath.row].id,
            profile: users[indexPath.row],
            isZombie: false,
            accessory: .tick(isSelected: selectedUsers.contains(users[indexPath.row].id))
        )
        
        return cell
    }

    // MARK: - Interaction
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if !selectedUsers.contains(users[indexPath.row].id) {
            selectedUsers.insert(users[indexPath.row].id)
        }
        else {
            selectedUsers.remove(users[indexPath.row].id)
        }
        
        tableView.deselectRow(at: indexPath, animated: true)
        tableView.reloadRows(at: [indexPath], with: .none)
    }

    @objc private func handleDoneButtonTapped() {
        completion(selectedUsers)
        navigationController!.popViewController(animated: true)
    }
}
