
final class UserSelectionVC : BaseVC, UITableViewDataSource {
    private let navBarTitle: String
    private let usersToExclude: Set<String>

    private lazy var users: [String] = {
        var result = ContactUtilities.getAllContacts()
        result.removeAll { usersToExclude.contains($0) }
        return result
    }()

    // MARK: Components
    @objc private lazy var tableView: UITableView = {
        let result = UITableView()
        result.dataSource = self
        result.register(UserCell.self, forCellReuseIdentifier: "UserCell")
        result.separatorStyle = .none
        result.backgroundColor = .clear
        result.showsVerticalScrollIndicator = false
        result.alwaysBounceVertical = false
        return result
    }()

    // MARK: Lifecycle
    @objc init(with title: String, excluding usersToExclude: Set<String>) {
        self.navBarTitle = title
        self.usersToExclude = usersToExclude
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { preconditionFailure("Use UserSelectionVC.init(excluding:) instead.") }
    override init(nibName: String?, bundle: Bundle?) { preconditionFailure("Use UserSelectionVC.init(excluding:) instead.") }

    override func viewDidLoad() {
        super.viewDidLoad()
        setUpGradientBackground()
        setUpNavBarStyle()
        setNavBarTitle(navBarTitle)
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
        cell.accessory = .tick(isSelected: false)
        cell.update()
        return cell
    }
}
