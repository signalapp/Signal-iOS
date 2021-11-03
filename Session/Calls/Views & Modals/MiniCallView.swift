import UIKit
import WebRTC

final class MiniCallView: UIView {
    var callVC: CallVC
    
    private lazy var remoteVideoView: RTCMTLVideoView = {
        let result = RTCMTLVideoView()
        result.contentMode = .scaleAspectFill
        return result
    }()
   
    // MARK: Initialization
    public static var current: MiniCallView?
    
    init(from callVC: CallVC) {
        self.callVC = callVC
        super.init(frame: CGRect.zero)
        self.backgroundColor = .black
        setUpViewHierarchy()
        setUpGestureRecognizers()
        MiniCallView.current = self
    }
    
    override init(frame: CGRect) {
        preconditionFailure("Use init(message:) instead.")
    }
    
    required init?(coder: NSCoder) {
        preconditionFailure("Use init(coder:) instead.")
    }
    
    private func setUpViewHierarchy() {
        self.set(.width, to: 80)
        self.set(.height, to: 173)
        // Background
        let background = getBackgroudView()
        self.addSubview(background)
        background.pin(to: self)
        // Remote video view
        callVC.call.attachRemoteVideoRenderer(remoteVideoView)
        self.addSubview(remoteVideoView)
        remoteVideoView.translatesAutoresizingMaskIntoConstraints = false
        remoteVideoView.pin(to: self)
    }
    
    private func getBackgroudView() -> UIView {
        let background = UIView()
        let imageView = UIImageView()
        imageView.layer.cornerRadius = 32
        imageView.layer.masksToBounds = true
        imageView.contentMode = .scaleAspectFill
        imageView.image = callVC.call.profilePicture
        background.addSubview(imageView)
        imageView.set(.width, to: 64)
        imageView.set(.height, to: 64)
        imageView.center(in: background)
        let blurView = UIView()
        blurView.alpha = 0.5
        blurView.backgroundColor = .black
        background.addSubview(blurView)
        blurView.autoPinEdgesToSuperviewEdges()
        return background
    }
    
    private func setUpGestureRecognizers() {
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tapGestureRecognizer.numberOfTapsRequired = 1
        addGestureRecognizer(tapGestureRecognizer)
        let panGestureRecognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
        addGestureRecognizer(panGestureRecognizer)
    }
    
    // MARK: Interaction
    @objc private func handleTap(_ gestureRecognizer: UITapGestureRecognizer) {
        dismiss()
        guard let presentingVC = CurrentAppContext().frontmostViewController() else { preconditionFailure() } // TODO: Handle more gracefully
        presentingVC.present(callVC, animated: true, completion: nil)
    }
    
    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let location = gesture.location(in: self.superview!)
        if let draggedView = gesture.view {
            draggedView.center = location
            if gesture.state == .ended {
                let sideMargin = 40 + Values.verySmallSpacing
                if draggedView.frame.midX >= self.superview!.layer.frame.width / 2 {
                    UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 1, options: .curveEaseIn, animations: {
                        draggedView.center.x = self.superview!.layer.frame.width - sideMargin
                    }, completion: nil)
                }else{
                    UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 1, options: .curveEaseIn, animations: {
                        draggedView.center.x = sideMargin
                    }, completion: nil)
                }
                let topMargin = UIApplication.shared.keyWindow!.safeAreaInsets.top + Values.veryLargeSpacing
                if draggedView.frame.minY <= topMargin {
                    UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 1, options: .curveEaseIn, animations: {
                        draggedView.center.y = topMargin + draggedView.frame.size.height / 2
                    }, completion: nil)
                }
                let bottomMargin = UIApplication.shared.keyWindow!.safeAreaInsets.bottom
                if draggedView.frame.maxY >= self.superview!.layer.frame.height {
                    UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 1, options: .curveEaseIn, animations: {
                        draggedView.center.y = self.layer.frame.height - draggedView.frame.size.height / 2 - bottomMargin
                    }, completion: nil)
                }
            }
        }
    }
    
    public func show() {
        self.alpha = 0.0
        let window = CurrentAppContext().mainWindow!
        window.addSubview(self)
        self.autoPinEdge(toSuperviewEdge: .right, withInset: Values.smallSpacing)
        let topMargin = UIApplication.shared.keyWindow!.safeAreaInsets.top + Values.veryLargeSpacing
        self.autoPinEdge(toSuperviewEdge: .top, withInset: topMargin)
        UIView.animate(withDuration: 0.5, delay: 0, options: [], animations: {
            self.alpha = 1.0
        }, completion: nil)
    }
    
    public func dismiss() {
        UIView.animate(withDuration: 0.5, delay: 0, options: [], animations: {
            self.alpha = 0.0
        }, completion: { _ in
            MiniCallView.current = nil
            self.removeFromSuperview()
        })
    }

}
