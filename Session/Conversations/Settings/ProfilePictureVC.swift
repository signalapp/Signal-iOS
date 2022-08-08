// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit

/// Shown when the user taps a profile picture in the conversation settings.
@objc(SNProfilePictureVC)
final class ProfilePictureVC: BaseVC {
    private let image: UIImage
    private let snTitle: String
    
    @objc init(image: UIImage, title: String) {
        self.image = image
        self.snTitle = title
        
        super.init(nibName: nil, bundle: nil)
    }
    
    override init(nibName: String?, bundle: Bundle?) {
        preconditionFailure("Use init(image:) instead.")
    }
    
    required init?(coder: NSCoder) {
        preconditionFailure("Use init(coder:) instead.")
    }
    
    override func viewDidLoad() {
        view.backgroundColor = .clear
        setUpGradientBackground()
        setUpNavBarStyle()
        setNavBarTitle(snTitle)
        // Close button
        let closeButton = UIBarButtonItem(image: #imageLiteral(resourceName: "X"), style: .plain, target: self, action: #selector(close))
        closeButton.tintColor = Colors.text
        navigationItem.leftBarButtonItem = closeButton
        // Image view
        let imageView = UIImageView(image: image)
        let size = UIScreen.main.bounds.width - 2 * Values.largeSpacing
        imageView.set(.width, to: size)
        imageView.set(.height, to: size)
        imageView.layer.cornerRadius = size / 2
        imageView.layer.masksToBounds = true
        view.addSubview(imageView)
        imageView.center(in: view)
        // Gesture recognizer
        let swipeGestureRecognizer = UISwipeGestureRecognizer(target: self, action: #selector(close))
        swipeGestureRecognizer.direction = .down
        view.addGestureRecognizer(swipeGestureRecognizer)
    }
    
    @objc private func close() {
        presentingViewController?.dismiss(animated: true, completion: nil)
    }
}
