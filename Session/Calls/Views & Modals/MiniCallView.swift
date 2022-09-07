// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import WebRTC
import SessionUIKit

final class MiniCallView: UIView, RTCVideoViewDelegate {
    var callVC: CallVC
    
    // MARK: UI
    private static let defaultSize: CGFloat = 100
    private let topMargin = (UIApplication.shared.keyWindow?.safeAreaInsets.top ?? 0) + Values.veryLargeSpacing
    private let bottomMargin = (UIApplication.shared.keyWindow?.safeAreaInsets.bottom ?? 0)
    
    private var width: NSLayoutConstraint?
    private var height: NSLayoutConstraint?
    private var left: NSLayoutConstraint?
    private var right: NSLayoutConstraint?
    private var top: NSLayoutConstraint?
    private var bottom: NSLayoutConstraint?
    
    private let backgroundView: UIView = {
        let result: UIView = UIView()
        result.themeBackgroundColor = .textPrimary
        result.alpha = 0.8
        
        return result
    }()
    
#if targetEnvironment(simulator)
    /// **Note:** `RTCMTLVideoView` doesn't seem to work on the simulator so use `RTCEAGLVideoView` instead
    ///
    /// Unfortunately this seems to have some issues on M1 macs where an `EXC_BAD_ACCESS` can be thrown when stopping and
    /// starting playback (eg. when swapping to the `MiniCallView` while on a video call, as such there isn't much we can do to
    /// resolve this issue but it should only occur on the Simulator on M1 Macs
    /// (see https://code.videolan.org/videolan/VLCKit/-/issues/566 for more information)
    private lazy var remoteVideoView: RTCEAGLVideoView = {
        let result = RTCEAGLVideoView()
        result.delegate = self
        result.themeBackgroundColor = .backgroundSecondary
        result.alpha = (self.callVC.call.isRemoteVideoEnabled ? 1 : 0)
        
        return result
    }()
#else
    private lazy var remoteVideoView: RTCMTLVideoView = {
        let result = RTCMTLVideoView()
        result.delegate = self
        result.videoContentMode = .scaleAspectFit
        result.themeBackgroundColor = .backgroundSecondary
        result.alpha = (self.callVC.call.isRemoteVideoEnabled ? 1 : 0)
        
        return result
    }()
#endif
   
    // MARK: - Initialization
    
    public static var current: MiniCallView?
    
    init(from callVC: CallVC) {
        self.callVC = callVC
        
        super.init(frame: CGRect.zero)
        
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
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowSubviewsChanged),
            name: .windowSubviewsChanged,
            object: nil
        )
    }
    
    override init(frame: CGRect) {
        preconditionFailure("Use init(message:) instead.")
    }
    
    required init?(coder: NSCoder) {
        preconditionFailure("Use init(coder:) instead.")
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    private func setUpViewHierarchy() {
        self.clipsToBounds = true
        self.layer.cornerRadius = 10
        self.width = self.set(.width, to: MiniCallView.defaultSize)
        self.height = self.set(.height, to: MiniCallView.defaultSize)
        
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
        let result: UIView = UIView()
        
        let background: UIView = UIView()
        background.themeBackgroundColor = .textPrimary
        background.alpha = 0.8
        result.addSubview(background)
        background.pin(to: result)
        
        let imageView = UIImageView()
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 32
        imageView.contentMode = .scaleAspectFill
        imageView.image = callVC.call.profilePicture
        result.addSubview(imageView)
        imageView.set(.width, to: 64)
        imageView.set(.height, to: 64)
        imageView.center(in: result)
        
        return result
    }
    
    private func setUpGestureRecognizers() {
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tapGestureRecognizer.numberOfTapsRequired = 1
        addGestureRecognizer(tapGestureRecognizer)
        makeViewDraggable()
    }
    
    // MARK: - Interaction
    
    @objc private func handleTap(_ gestureRecognizer: UITapGestureRecognizer) {
        dismiss()
        guard let presentingVC = CurrentAppContext().frontmostViewController() else { preconditionFailure() } // FIXME: Handle more gracefully
        presentingVC.present(callVC, animated: true, completion: nil)
    }
    
    public func show() {
        self.alpha = 0.0
        guard let window: UIWindow = CurrentAppContext().mainWindow else { return }
        
        window.addSubview(self)
        left = self.autoPinEdge(toSuperviewEdge: .left)
        left?.isActive = false
        right = self.autoPinEdge(toSuperviewEdge: .right, withInset: Values.smallSpacing)
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
        }, completion: { [weak self] _ in
            if let remoteVideoView: RTCVideoRenderer = self?.remoteVideoView {
                self?.callVC.call.removeRemoteVideoRenderer(remoteVideoView)
            }
            
            self?.callVC.setupStateChangeCallbacks()
            MiniCallView.current = nil
            self?.removeFromSuperview()
        })
    }
    
    // MARK: - RTCVideoViewDelegate
    
    func videoView(_ videoView: RTCVideoRenderer, didChangeVideoSize size: CGSize) {
        let newSize = CGSize(
            width: min(160.0, 160.0 * size.width / size.height),
            height: min(160.0, 160.0 * size.height / size.width)
        )
        persistCurrentPosition(newSize: newSize)
        self.width?.constant = newSize.width
        self.height?.constant = newSize.height
    }
    
    func persistCurrentPosition(newSize: CGSize) {
        let currentCenter = self.center
        
        if currentCenter.x < ((self.superview?.width() ?? 0) / 2) {
            left?.isActive = true
            right?.isActive = false
        }
        else {
            left?.isActive = false
            right?.isActive = true
        }
        
        let willTouchTop: Bool = (currentCenter.y < ((newSize.height / 2) + topMargin))
        let willTouchBottom: Bool = ((currentCenter.y + (newSize.height / 2)) >= (self.superview?.height() ?? 0))
        
        if willTouchBottom {
            top?.isActive = false
            bottom?.isActive = true
        }
        else {
            let constant = (willTouchTop ? topMargin : (currentCenter.y - (newSize.height / 2)))
            top?.constant = constant
            top?.isActive = true
            bottom?.isActive = false
        }
    }

    @objc private func windowSubviewsChanged() {
        // Ensure the MiniCallView always stays in front when presenting screens (need to update the
        // constraints to match the current values so when the re-layout occurs it doesn't move)
        if self.top?.isActive == true {
            self.top?.constant = self.frame.minY
        }
        
        if self.left?.isActive == true {
            self.left?.constant = self.frame.minX
        }
        
        if self.right?.isActive == true {
            self.right?.constant = (self.frame.maxX - (self.superview?.width() ?? 0))
        }
        
        if self.bottom?.isActive == true {
            self.bottom?.constant = (self.frame.maxY - (self.superview?.height() ?? 0))
        }
        
        self.window?.bringSubviewToFront(self)
    }
}
