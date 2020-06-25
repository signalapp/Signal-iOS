
// MARK: - Device Links View Controller

@objc(LKDeviceLinksVC)
final class DeviceLinksVC : BaseVC, UITableViewDataSource, UITableViewDelegate, DeviceLinkingModalDelegate, DeviceNameModalDelegate {
    private var deviceLinks: [DeviceLink] = [] { didSet { updateUI() } }
    
    // MARK: Components
    private lazy var tableView: UITableView = {
        let result = UITableView()
        result.dataSource = self
        result.delegate = self
        result.register(Cell.self, forCellReuseIdentifier: "Cell")
        result.separatorStyle = .none
        result.backgroundColor = .clear
        return result
    }()
    
    private lazy var callToActionView : UIStackView = {
        let explanationLabel = UILabel()
        explanationLabel.textColor = Colors.text
        explanationLabel.font = .systemFont(ofSize: Values.smallFontSize)
        explanationLabel.numberOfLines = 0
        explanationLabel.lineBreakMode = .byWordWrapping
        explanationLabel.textAlignment = .center
        explanationLabel.text = NSLocalizedString("You haven't linked any devices yet", comment: "")
        let linkNewDeviceButton = Button(style: .prominentOutline, size: .large)
        linkNewDeviceButton.setTitle(NSLocalizedString("Link a Device (Beta)", comment: ""), for: UIControl.State.normal)
        linkNewDeviceButton.addTarget(self, action: #selector(linkNewDevice), for: UIControl.Event.touchUpInside)
        linkNewDeviceButton.set(.width, to: 180)
        let result = UIStackView(arrangedSubviews: [ explanationLabel, linkNewDeviceButton ])
        result.axis = .vertical
        result.spacing = Values.mediumSpacing
        result.alignment = .center
        return result
    }()
    
    // MARK: Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setUpGradientBackground()
        setUpNavBarStyle()
        setNavBarTitle(NSLocalizedString("Devices", comment: ""))
        // Set up link new device button
        let linkNewDeviceButton = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(linkNewDevice))
        linkNewDeviceButton.tintColor = Colors.text
        navigationItem.rightBarButtonItem = linkNewDeviceButton
        // Set up constraints
        view.addSubview(tableView)
        tableView.pin(to: view)
        view.addSubview(callToActionView)
        callToActionView.center(.horizontal, in: view)
        let verticalCenteringConstraint = callToActionView.center(.vertical, in: view)
        verticalCenteringConstraint.constant = -16 // Makes things appear centered visually
        // Perform initial update
        updateDeviceLinks()
    }
    
    // MARK: Data
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return deviceLinks.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell") as! Cell
        let selectedBackgroundView = UIView()
        selectedBackgroundView.backgroundColor = Colors.cellSelected
        cell.selectedBackgroundView = selectedBackgroundView
        let device = deviceLinks[indexPath.row].other
        cell.device = device
        return cell
    }
    
    // MARK: Updating
    private func updateDeviceLinks() {
        let storage = OWSPrimaryStorage.shared()
        let userHexEncodedPublicKey = getUserHexEncodedPublicKey()
        var deviceLinks: [DeviceLink] = []
        storage.dbReadConnection.read { transaction in
            deviceLinks = storage.getDeviceLinks(for: userHexEncodedPublicKey, in: transaction).sorted { lhs, rhs in
                return lhs.other.hexEncodedPublicKey > rhs.other.hexEncodedPublicKey
            }
        }
        self.deviceLinks = deviceLinks
    }
    
    private func updateUI() {
        tableView.reloadData()
        UIView.animate(withDuration: 0.25) {
            self.callToActionView.isHidden = !self.deviceLinks.isEmpty
        }
    }
    
    func handleDeviceLinkAuthorized(_ deviceLink: DeviceLink) {
        // The modal already dismisses itself
        updateDeviceLinks()
    }
    
    func handleDeviceLinkingModalDismissed() {
        // Do nothing
    }
    
    // MARK: Interaction
    @objc private func linkNewDevice() {
        if deviceLinks.isEmpty {
            let deviceLinkingModal = DeviceLinkingModal(mode: .master, delegate: self)
            deviceLinkingModal.modalPresentationStyle = .overFullScreen
            deviceLinkingModal.modalTransitionStyle = .crossDissolve
            present(deviceLinkingModal, animated: true, completion: nil)
        } else {
            let alert = UIAlertController(title: NSLocalizedString("Multi Device Limit Reached", comment: ""), message: NSLocalizedString("It's currently not allowed to link more than one device.", comment: ""), preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default, handler: nil))
            present(alert, animated: true, completion: nil)
        }
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        defer { tableView.deselectRow(at: indexPath, animated: true) }
        let deviceLink = deviceLinks[indexPath.row]
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: NSLocalizedString("Change Name", comment: ""), style: .default) { [weak self] _ in
            guard let self = self else { return }
            let deviceNameModal = DeviceNameModal()
            deviceNameModal.device = deviceLink.other
            deviceNameModal.delegate = self
            deviceNameModal.modalPresentationStyle = .overFullScreen
            deviceNameModal.modalTransitionStyle = .crossDissolve
            self.present(deviceNameModal, animated: true, completion: nil)
        })
        sheet.addAction(UIAlertAction(title: NSLocalizedString("Unlink", comment: ""), style: .destructive) { [weak self] _ in
            self?.removeDeviceLink(deviceLink)
        })
        sheet.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel) { _ in })
        present(sheet, animated: true, completion: nil)
    }
    
    @objc func handleDeviceNameChanged(to name: String, for device: DeviceLink.Device) {
        dismiss(animated: true, completion: nil)
        updateUI()
    }
    
    private func removeDeviceLink(_ deviceLink: DeviceLink) {
        FileServerAPI.removeDeviceLink(deviceLink).done { [weak self] in
            let linkedDeviceHexEncodedPublicKey = deviceLink.other.hexEncodedPublicKey
            guard let thread = TSContactThread.fetch(uniqueId: TSContactThread.threadId(fromContactId: linkedDeviceHexEncodedPublicKey)) else { return }
            let unlinkDeviceMessage = UnlinkDeviceMessage(thread: thread)
            SSKEnvironment.shared.messageSender.send(unlinkDeviceMessage, success: {
                let storage = OWSPrimaryStorage.shared()
                try! Storage.writeSync { transaction in
                    storage.removePreKeyBundle(forContact: linkedDeviceHexEncodedPublicKey, transaction: transaction)
                    storage.deleteAllSessions(forContact: linkedDeviceHexEncodedPublicKey, protocolContext: transaction)
                }
            }, failure: { _ in
                print("[Loki] Failed to send unlink device message.")
                let storage = OWSPrimaryStorage.shared()
                try! Storage.writeSync { transaction in
                    storage.removePreKeyBundle(forContact: linkedDeviceHexEncodedPublicKey, transaction: transaction)
                    storage.deleteAllSessions(forContact: linkedDeviceHexEncodedPublicKey, protocolContext: transaction)
                }
            })
            self?.updateDeviceLinks()
        }.catch { [weak self] _ in
            let alert = UIAlertController(title: NSLocalizedString("Couldn't Unlink Device", comment: ""), message: NSLocalizedString("Please check your internet connection and try again", comment: ""), preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), accessibilityIdentifier: nil, style: .default, handler: nil))
            self?.present(alert, animated: true, completion: nil)
        }
    }
}

// MARK: - Cell

private extension DeviceLinksVC {
    
    final class Cell : UITableViewCell {
        var device: DeviceLink.Device! { didSet { update() } }
        
        // MARK: Components
        private lazy var titleLabel: UILabel = {
            let result = UILabel()
            result.textColor = Colors.text
            result.font = .boldSystemFont(ofSize: Values.mediumFontSize)
            result.lineBreakMode = .byTruncatingTail
            return result
        }()
        
        private lazy var subtitleLabel: UILabel = {
            let result = UILabel()
            result.textColor = Colors.text
            result.font = .systemFont(ofSize: Values.smallFontSize)
            result.lineBreakMode = .byTruncatingTail
            return result
        }()
        
        // MARK: Initialization
        override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
            super.init(style: style, reuseIdentifier: reuseIdentifier)
            setUpViewHierarchy()
        }
        
        required init?(coder: NSCoder) {
            super.init(coder: coder)
            setUpViewHierarchy()
        }
        
        private func setUpViewHierarchy() {
            backgroundColor = Colors.cellBackground
            let stackView = UIStackView(arrangedSubviews: [ titleLabel, subtitleLabel ])
            stackView.axis = .vertical
            stackView.distribution = .equalCentering
            stackView.spacing = Values.verySmallSpacing
            stackView.set(.height, to: 44)
            contentView.addSubview(stackView)
            stackView.pin(.leading, to: .leading, of: contentView, withInset: Values.largeSpacing)
            stackView.pin(.top, to: .top, of: contentView, withInset: 12)
            contentView.pin(.trailing, to: .trailing, of: stackView, withInset: Values.largeSpacing)
            contentView.pin(.bottom, to: .bottom, of: stackView, withInset: 12)
            stackView.set(.width, to: UIScreen.main.bounds.width - 2 * Values.largeSpacing)
        }
        
        // MARK: Updating
        private func update() {
            titleLabel.text = device.displayName
            subtitleLabel.text = Mnemonic.hash(hexEncodedString: device.hexEncodedPublicKey.removing05PrefixIfNeeded())
        }
    }
}
