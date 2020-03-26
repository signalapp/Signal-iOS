
class BaseVC : UIViewController {

    override var preferredStatusBarStyle: UIStatusBarStyle { return isLightMode ? .default : .lightContent }

    override func viewDidLoad() {
        setNeedsStatusBarAppearanceUpdate()
        NotificationCenter.default.addObserver(self, selector: #selector(handleUnexpectedDeviceLinkRequestReceivedNotification), name: .unexpectedDeviceLinkRequestReceived, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handleUnexpectedDeviceLinkRequestReceivedNotification() {
        guard DeviceLinkingUtilities.shouldShowUnexpectedDeviceLinkRequestReceivedAlert else { return }
        DispatchQueue.main.async {
            let alert = UIAlertController(title: "Device Link Request Received", message: "Open the device link screen by going to \"Settings\" > \"Devices\" > \"Link a Device\" to link your devices.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
            self.present(alert, animated: true, completion: nil)
        }
    }
}
