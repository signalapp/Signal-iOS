
@objc(LKModal)
internal class Modal : UIViewController {
    
    // MARK: Components
    lazy var contentView: UIView = {
        let result = UIView()
        result.backgroundColor = .lokiDarkGray()
        result.layer.cornerRadius = 4
        result.layer.masksToBounds = false
        result.layer.shadowColor = UIColor.black.cgColor
        result.layer.shadowRadius = 8
        result.layer.shadowOpacity = 0.64
        return result
    }()
    
    lazy var cancelButton: OWSFlatButton = {
        let result = OWSFlatButton.button(title: NSLocalizedString("Cancel", comment: ""), font: .ows_dynamicTypeBodyClamped, titleColor: .white, backgroundColor: .clear, target: self, selector: #selector(cancel))
        result.setBackgroundColors(upColor: .clear, downColor: .clear)
        return result
    }()
    
    // MARK: Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setUpViewHierarchy()
    }
    
    private func setUpViewHierarchy() {
        view.backgroundColor = .clear
        view.addSubview(contentView)
        contentView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32).isActive = true
        view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: 32).isActive = true
        contentView.center(.vertical, in: view)
        populateContentView()
    }
    
    /// To be overridden by subclasses.
    func populateContentView() {
        preconditionFailure("populateContentView() is abstract and must be overridden.")
    }
    
    // MARK: Interaction
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        let touch = touches.first!
        let location = touch.location(in: view)
        if contentView.frame.contains(location) {
            super.touchesBegan(touches, with: event)
        } else {
            cancel()
        }
    }
    
    @objc func cancel() {
        dismiss(animated: true, completion: nil)
    }
}
