//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

protocol ContextMenuControllerDelegate : AnyObject {
    func contextMenuControllerRequestsDismissal(_ contextMenuController: ContextMenuController)
}

class ContextMenuView : UIView {
    var blurView: UIView? {
        willSet {
            if let view = blurView {
                view.removeFromSuperview()
            }
        }
        didSet {
            oldValue?.removeFromSuperview()
            
            if let view = blurView {
                addSubview(view)
            }
        }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        blurView?.frame = bounds
    }
}

class ContextMenuController : UIViewController {
    weak var delegate: ContextMenuControllerDelegate?
    
    let contextMenuPreview: ContextMenuTargetedPreview
    let contextMenuConfiguration: ContextMenuConfiguration //Do we want this or a UIMenu
    
    lazy var blurView: UIVisualEffectView = {
        let effect = UIBlurEffect(style: UIBlurEffect.Style.regular)
        return UIVisualEffectView(effect: effect)
    }()
    
    init(configuration: ContextMenuConfiguration, preview: ContextMenuTargetedPreview) {
        self.contextMenuConfiguration = configuration
        self.contextMenuPreview = preview
        
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    //MARK: UIViewController
    
    override func loadView() {
        let contextMenuView = ContextMenuView(frame: CGRect.zero)
        contextMenuView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.view = contextMenuView
        
        contextMenuView.blurView = blurView
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(tapGestureRecogznied(sender:)))
        self.view.addGestureRecognizer(tapGesture)
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let bounds = self.view.bounds
        blurView.bounds = bounds
    }
    
    //MARK: Private

    @objc
    private func tapGestureRecogznied(sender: UIGestureRecognizer) {
        delegate?.contextMenuControllerRequestsDismissal(self)
    }
}
