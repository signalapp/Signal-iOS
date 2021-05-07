
@objc(SNUserSelectionVC)
final class UserSelectionVC : BaseVC, UITableViewDataSource, UITableViewDelegate {
    private let navBarTitle: String
    private let usersToExclude: Set<String>
    private let completion: (Set<String>) -> Void
    private var selectedUsers: Set<String> = []

    private lazy var users: [String] = {
        var result = ContactUtilities.getAllContacts()
        result.removeAll { usersToExclude.contains($0) }
        return result
    }()

    // MARK: Components
    @objc private lazy var tableView: UITableView = {
        let result = UITableView()
        result.dataSource = self
        result.delegate = self
        result.register(UserCell.self, forCellReuseIdentifier: "UserCell")
        result.separatorStyle = .none
        result.backgroundColor = .clear
        result.showsVerticalScrollIndicator = false
        result.alwaysBounceVertical = false
        return result
    }()

    // MARK: Lifecycle
    @objc(initWithTitle:excluding:completion:)
    init(with title: String, excluding usersToExclude: Set<String>, completion: @escaping (Set<String>) -> Void) {
        self.navBarTitle = title
        self.usersToExclude = usersToExclude
        self.completion = completion
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { preconditionFailure("Use UserSelectionVC.init(excluding:) instead.") }
    override init(nibName: String?, bundle: Bundle?) { preconditionFailure("Use UserSelectionVC.init(excluding:) instead.") }

    override func viewDidLoad() {
        super.viewDidLoad()
        setUpGradientBackground()
        setUpNavBarStyle()
        setNavBarTitle(navBarTitle)
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(handleDoneButtonTapped))
        view.addSubview(tableView)
        tableView.pin(to: view)
    }

    // MARK: Data
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return users.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "UserCell") as! UserCell
        let publicKey = users[indexPath.row]
        cell.publicKey = publicKey
        let isSelected = selectedUsers.contains(publicKey)
        cell.accessory = .tick(isSelected: isSelected)
        cell.update()
        return cell
    }

    // MARK: Interaction
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let publicKey = users[indexPath.row]
        if !selectedUsers.contains(publicKey) { selectedUsers.insert(publicKey) } else { selectedUsers.remove(publicKey) }
        guard let cell = tableView.cellForRow(at: indexPath) as? UserCell else { return }
        let isSelected = selectedUsers.contains(publicKey)
        cell.accessory = .tick(isSelected: isSelected)
        cell.update()
    }

    @objc private func handleDoneButtonTapped() {
        completion(selectedUsers)
        navigationController!.popViewController(animated: true)
    }
}
