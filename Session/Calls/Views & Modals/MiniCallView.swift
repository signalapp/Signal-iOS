import UIKit
import WebRTC

final class MiniCallView: UIView, RTCVideoViewDelegate {
    var callVC: CallVC
    
    // MARK: UI
    private static let defaultSize: CGFloat = UIDevice.current.isIPad ? 200 : 100
    private static let defaultVideoSize: CGFloat = UIDevice.current.isIPad ? 320 : 160
    private let topMargin = UIApplication.shared.keyWindow!.safeAreaInsets.top + Values.veryLargeSpacing
    private let bottomMargin = UIApplication.shared.keyWindow!.safeAreaInsets.bottom
    
    private var width: NSLayoutConstraint?
    private var height: NSLayoutConstraint?
    private var left: NSLayoutConstraint?
    private var right: NSLayoutConstraint?
    private var top: NSLayoutConstraint?
    private var bottom: NSLayoutConstraint?
    
#if targetEnvironment(simulator)
    // Note: 'RTCMTLVideoView' doesn't seem to work on the simulator so use 'RTCEAGLVideoView' instead
    private lazy var remoteVideoView: RTCEAGLVideoView = {
        let result = RTCEAGLVideoView()
        result.delegate = self
        result.alpha = self.callVC.call.isRemoteVideoEnabled ? 1 : 0
        result.backgroundColor = .black
        return result
    }()
#else
    private lazy var remoteVideoView: RTCMTLVideoView = {
        let result = RTCMTLVideoView()
        result.delegate = self
        result.alpha = self.callVC.call.isRemoteVideoEnabled ? 1 : 0
        result.videoContentMode = .scaleAspectFit
        result.backgroundColor = .black
        return result
    }()
#endif
   
    // MARK: Initialization
    public static var current: MiniCallView?
    
    init(from callVC: CallVC) {
        self.callVC = callVC
        super.init(frame: CGRect.zero)
        self.backgroundColor = UIColor.init(white: 0, alpha: 0.8)
        setUpViewHierarchy()
        setUpGestureRecognizers()
        MiniCallView.current = self
        self.callVC.call.remoteVideoStateDidChange = { isEnabled in
            DispatchQueue.main.async {
                UIView.animate(withDuration: 0.25) {
                    self.remoteVideoView.alpha = isEnabled ? 1 : 0
                    if !isEnabled {
                        self.width?.constant = MiniCallView.defaultSize
                        self.height?.constant = MiniCallView.defaultSize
                    }
                }
            }
        }
    }
    
    override init(frame: CGRect) {
        preconditionFailure("Use init(message:) instead.")
    }
    
    required init?(coder: NSCoder) {
        preconditionFailure("Use init(coder:) instead.")
    }
    
    private func setUpViewHierarchy() {
        self.width = self.set(.width, to: MiniCallView.defaultSize)
        self.height = self.set(.height, to: MiniCallView.defaultSize)
        self.layer.cornerRadius = UIDevice.current.isIPad ? 20 : 10
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
        guard let presentingVC = CurrentAppContext().frontmostViewController() else { preconditionFailure() } // FIXME: Handle more gracefully
        presentingVC.present(callVC, animated: true, completion: nil)
    }
    
    public func show() {
        self.alpha = 0.0
        let window = CurrentAppContext().mainWindow!
        window.addSubview(self)
        left = self.autoPinEdge(toSuperviewEdge: .left)
        left?.isActive = false
        right = self.autoPinEdge(toSuperviewEdge: .right)
        top = self.autoPinEdge(toSuperviewEdge: .top, withInset: topMargin)
        bottom = self.autoPinEdge(toSuperviewEdge: .bottom, withInset: bottomMargin)
        bottom?.isActive = false
        UIView.animate(withDuration: 0.5, delay: 0, options: [], animations: {
            self.alpha = 1.0
        }, completion: nil)
    }
    
    public func dismiss() {
        UIView.animate(withDuration: 0.5, delay: 0, options: [], animations: {
            self.alpha = 0.0
        }, completion: { _ in
            self.callVC.call.removeRemoteVideoRenderer(self.remoteVideoView)
            self.callVC.setupStateChangeCallbacks()
            MiniCallView.current = nil
            self.removeFromSuperview()
        })
    }
    
    // MARK: RTCVideoViewDelegate
    func videoView(_ videoView: RTCVideoRenderer, didChangeVideoSize size: CGSize) {
        let newSize = CGSize(
            width: min(Self.defaultVideoSize, Self.defaultVideoSize * size.width / size.height),
            height: min(Self.defaultVideoSize, Self.defaultVideoSize * size.height / size.width)
        )
        persistCurrentPosition(newSize: newSize)
        self.width?.constant = newSize.width
        self.height?.constant = newSize.height
    }
    
    func persistCurrentPosition(newSize: CGSize) {
        let currentCenter = self.center
        
        if currentCenter.x < self.superview!.width() / 2 {
            left?.isActive = true
            right?.isActive = false
        } else {
            left?.isActive = false
            right?.isActive = true
        }
        
        let willTouchTop = currentCenter.y < newSize.height / 2 + topMargin
        let willTouchBottom = currentCenter.y + newSize.height / 2 >= self.superview!.height()
        if willTouchBottom {
            top?.isActive = false
            bottom?.isActive = true
        } else {
            let constant = willTouchTop ? topMargin : currentCenter.y - newSize.height / 2
            top?.constant = constant
            top?.isActive = true
            bottom?.isActive = false
        }
    }

}
