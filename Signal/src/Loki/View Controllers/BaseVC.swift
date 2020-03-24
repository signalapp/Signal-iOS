
class BaseVC : UIViewController {

    override var preferredStatusBarStyle: UIStatusBarStyle { return isLightMode ? .default : .lightContent }

    override func viewDidLoad() {
        setNeedsStatusBarAppearanceUpdate()
    }
}
