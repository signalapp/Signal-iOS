
@objc(LKModal)
class Modal : BaseVC {
    private(set) var verticalCenteringConstraint: NSLayoutConstraint!
    
    // MARK: Components
    lazy var contentView: UIView = {
        let result = UIView()
        result.backgroundColor = Colors.modalBackground
        result.layer.cornerRadius = Values.modalCornerRadius
        result.layer.masksToBounds = false
        result.layer.borderColor = isLightMode ? UIColor.white.cgColor : Colors.modalBorder.cgColor
        result.layer.borderWidth = Values.borderThickness
        result.layer.shadowColor = UIColor.black.cgColor
        result.layer.shadowRadius = isLightMode ? 2 : 8
        result.layer.shadowOpacity = isLightMode ? 0.1 : 0.64
        return result
    }()
    
    lazy var cancelButton: UIButton = {
        let result = UIButton()
        result.set(.height, to: Values.mediumButtonHeight)
        result.layer.cornerRadius = Values.modalButtonCornerRadius
        result.backgroundColor = Colors.buttonBackground
        result.titleLabel!.font = .systemFont(ofSize: Values.smallFontSize)
        result.setTitleColor(Colors.text, for: UIControl.State.normal)
        result.setTitle(NSLocalizedString("cancel", comment: ""), for: UIControl.State.normal)
        return result
    }()
    
    // MARK: Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        let alpha = isLightMode ? CGFloat(0.1) : Values.modalBackgroundOpacity
        view.backgroundColor = UIColor(hex: 0x000000).withAlphaComponent(alpha)
        cancelButton.addTarget(self, action: #selector(close), for: UIControl.Event.touchUpInside)
        let swipeGestureRecognizer = UISwipeGestureRecognizer(target: self, action: #selector(close))
        swipeGestureRecognizer.direction = .down
        view.addGestureRecognizer(swipeGestureRecognizer)
        setUpViewHierarchy()
    }
    
    private func setUpViewHierarchy() {
        view.addSubview(contentView)
        contentView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Values.veryLargeSpacing).isActive = true
        view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: Values.veryLargeSpacing).isActive = true
        verticalCenteringConstraint = contentView.center(.vertical, in: view)
        populateContentView()
    }
    
    /// To be overridden by subclasses.
    func populateContentView() {
        preconditionFailure("populateContentView() is abstract and must be overridden.")
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
//        verticalCenteringConstraint.constant = contentView.height() / 2 + view.height() / 2
//        view.layoutIfNeeded()
//        verticalCenteringConstraint.constant = 0
//        UIView.animate(withDuration: 0.25) {
//            self.view.layoutIfNeeded()
//        }
    }
    
    // MARK: Interaction
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        let touch = touches.first!
        let location = touch.location(in: view)
        if contentView.frame.contains(location) {
            super.touchesBegan(touches, with: event)
        } else {
            close()
        }
    }
    
    @objc func close() {
        dismiss(animated: true, completion: nil)
    }
}
