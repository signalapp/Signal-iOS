import UIKit
import WebRTC

final class MiniCallView: UIView {
    var callVC: CallVC
    
    private lazy var remoteVideoView: RemoteVideoView = {
        let result = RemoteVideoView()
        result.alpha = 0
        result.videoContentMode = .scaleAspectFit
        result.backgroundColor = .black
        return result
    }()
   
    // MARK: Initialization
    public static var current: MiniCallView?
    
    init(from callVC: CallVC) {
        self.callVC = callVC
        super.init(frame: CGRect.zero)
        self.backgroundColor = UIColor.init(white: 0, alpha: 0.8)
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
        self.set(.width, to: 100)
        self.set(.height, to: 100)
        self.layer.cornerRadius = 10
        self.layer.masksToBounds = true
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
        return background
    }
    
    private func setUpGestureRecognizers() {
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tapGestureRecognizer.numberOfTapsRequired = 1
        addGestureRecognizer(tapGestureRecognizer)
        makeViewDraggable()
    }
    
    // MARK: Interaction
    @objc private func handleTap(_ gestureRecognizer: UITapGestureRecognizer) {
        dismiss()
        guard let presentingVC = CurrentAppContext().frontmostViewController() else { preconditionFailure() } // TODO: Handle more gracefully
        presentingVC.present(callVC, animated: true, completion: nil)
    }
    
    public func show() {
        self.alpha = 0.0
        let window = CurrentAppContext().mainWindow!
        window.addSubview(self)
        self.autoPinEdge(toSuperviewEdge: .right)
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
            self.callVC.call.removeRemoteVideoRenderer(self.remoteVideoView)
            MiniCallView.current = nil
            self.removeFromSuperview()
        })
    }

}
