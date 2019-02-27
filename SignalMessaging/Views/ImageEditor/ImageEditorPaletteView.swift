//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import UIKit

public protocol ImageEditorPaletteViewDelegate: class {
    func selectedColorDidChange()
}

// MARK: -

public class ImageEditorPaletteView: UIView {

    public weak var delegate: ImageEditorPaletteViewDelegate?

    public required init() {
        super.init(frame: .zero)

        createContents()
    }

    @available(*, unavailable, message: "use other init() instead.")
    required public init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    // MARK: - Views

    // The actual default is selected later.
    public var selectedColor = UIColor.white

    private let imageView = UIImageView()
    private let selectionView = UIView()
    private let selectionWrapper = OWSLayerView()
    private var selectionConstraint: NSLayoutConstraint?

    private func createContents() {
        self.backgroundColor = .clear
        self.isOpaque = false

        if let image = ImageEditorPaletteView.buildPaletteGradientImage() {
            imageView.image = image
            imageView.layer.cornerRadius = image.size.width * 0.5
            imageView.clipsToBounds = true
        } else {
            owsFailDebug("Missing image.")
        }
        addSubview(imageView)
        // We use an invisible margin to expand the hot area of
        // this control.
        let margin: CGFloat = 8
        imageView.autoPinEdgesToSuperviewEdges(with: UIEdgeInsets(top: margin, left: margin, bottom: margin, right: margin))

        selectionWrapper.layoutCallback = { [weak self] (view) in
            guard let strongSelf = self else {
                return
            }
            strongSelf.updateState()
        }
        self.addSubview(selectionWrapper)
        selectionWrapper.autoPin(toEdgesOf: imageView)

        selectionView.addBorder(with: .white)
        selectionView.layer.cornerRadius = selectionSize / 2
        selectionView.autoSetDimensions(to: CGSize(width: selectionSize, height: selectionSize))
        selectionWrapper.addSubview(selectionView)
        selectionView.autoHCenterInSuperview()

        // There must be a better way to pin the selection view's location,
        // but I can't find it.
        let selectionConstraint = NSLayoutConstraint(item: selectionView,
                                                     attribute: .centerY, relatedBy: .equal, toItem: selectionWrapper, attribute: .top, multiplier: 1, constant: 0)
        selectionConstraint.autoInstall()
        self.selectionConstraint = selectionConstraint

        isUserInteractionEnabled = true
        addGestureRecognizer(PaletteGestureRecognizer(target: self, action: #selector(didTouch)))

        updateState()
    }

    // 0 = the color at the top of the image is selected.
    // 1 = the color at the bottom of the image is selected.
    private let selectionSize: CGFloat = 20
    private var selectionAlpha: CGFloat = 0

    private func selectColor(atLocationY y: CGFloat) {
        selectionAlpha = y.inverseLerp(0, imageView.height(), shouldClamp: true)

        updateState()

        delegate?.selectedColorDidChange()
    }

    private func updateState() {
        var selectedColor = UIColor.white
        if let image = imageView.image {
            if let imageColor = image.color(atLocation: CGPoint(x: CGFloat(image.size.width) * 0.5, y: CGFloat(image.size.height) * selectionAlpha)) {
                selectedColor = imageColor
            } else {
                owsFailDebug("Couldn't determine image color.")
            }
        } else {
            owsFailDebug("Missing image.")
        }
        self.selectedColor = selectedColor

        selectionView.backgroundColor = selectedColor

        guard let selectionConstraint = selectionConstraint else {
            owsFailDebug("Missing selectionConstraint.")
            return
        }
        let selectionY = selectionWrapper.height() * selectionAlpha
        selectionConstraint.constant = selectionY
    }

    // MARK: Events

    @objc
    func didTouch(gesture: UIGestureRecognizer) {
        Logger.verbose("gesture: \(NSStringForUIGestureRecognizerState(gesture.state))")
        switch gesture.state {
        case .began, .changed, .ended:
            break
        default:
            return
        }

        let location = gesture.location(in: imageView)
        selectColor(atLocationY: location.y)
    }

    private static func buildPaletteGradientImage() -> UIImage? {
        let gradientSize = CGSize(width: 8, height: 200)
        let gradientBounds = CGRect(origin: .zero, size: gradientSize)
        let gradientView = UIView()
        gradientView.frame = gradientBounds
        let gradientLayer = CAGradientLayer()
        gradientView.layer.addSublayer(gradientLayer)
        gradientLayer.frame = gradientBounds
        // See: https://github.com/signalapp/Signal-Android/blob/master/res/values/arrays.xml#L267
        gradientLayer.colors = [
            UIColor(rgbHex: 0xffffff).cgColor,
            UIColor(rgbHex: 0xff0000).cgColor,
            UIColor(rgbHex: 0xff00ff).cgColor,
            UIColor(rgbHex: 0x0000ff).cgColor,
            UIColor(rgbHex: 0x00ffff).cgColor,
            UIColor(rgbHex: 0x00ff00).cgColor,
            UIColor(rgbHex: 0xffff00).cgColor,
            UIColor(rgbHex: 0xff5500).cgColor,
            UIColor(rgbHex: 0x000000).cgColor
        ]
        gradientLayer.startPoint = CGPoint.zero
        gradientLayer.endPoint = CGPoint(x: 0, y: gradientSize.height)
        gradientLayer.endPoint = CGPoint(x: 0, y: 1.0)
        return gradientView.renderAsImage(opaque: true, scale: UIScreen.main.scale)
    }
}

// MARK: -

extension UIImage {
    func color(atLocation locationPoints: CGPoint) -> UIColor? {
        guard let cgImage = cgImage else {
            owsFailDebug("Missing cgImage.")
            return nil
        }
        guard let dataProvider = cgImage.dataProvider else {
            owsFailDebug("Could not create dataProvider.")
            return nil
        }
        guard let pixelData = dataProvider.data else {
            owsFailDebug("dataProvider has no data.")
            return nil
        }
        let bytesPerPixel: Int = cgImage.bitsPerPixel / 8
        guard bytesPerPixel == 4 else {
            owsFailDebug("Invalid bytesPerPixel: \(bytesPerPixel).")
            return nil
        }
        let imageWidth: Int = cgImage.width
        let imageHeight: Int = cgImage.height
        guard imageWidth > 0,
            imageHeight > 0 else {
                owsFailDebug("Invalid image size.")
                return nil
        }

        Logger.verbose("scale: \(self.scale)")

        // Convert the location from points to pixels and clamp to the image bounds.
        let xPixels: Int = Int(round(locationPoints.x * self.scale)).clamp(0, imageWidth - 1)
        let yPixels: Int = Int(round(locationPoints.y * self.scale)).clamp(0, imageHeight - 1)
        let dataLength = (pixelData as Data).count
        let data: UnsafePointer<UInt8> = CFDataGetBytePtr(pixelData)
        let index: Int = (imageWidth * yPixels + xPixels) * bytesPerPixel
        guard index >= 0, index < dataLength else {
            owsFailDebug("Invalid index.")
            return nil
        }

        let red = CGFloat(data[index]) / CGFloat(255.0)
        let green = CGFloat(data[index+1]) / CGFloat(255.0)
        let blue = CGFloat(data[index+2]) / CGFloat(255.0)
        let alpha = CGFloat(data[index+3]) / CGFloat(255.0)

        return UIColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}

// MARK: -

// The most permissive GR possible. Accepts any number of touches in any locations.
private class PaletteGestureRecognizer: UIGestureRecognizer {

    @objc
    public override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool {
        return false
    }

    @objc
    public override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool {
        return false
    }

    @objc
    public override func shouldRequireFailure(of otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return false
    }

    @objc
    public override func shouldBeRequiredToFail(by otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return false
    }

    @objc
    public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        handle(event: event)
    }

    @objc
    public override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        handle(event: event)
    }

    @objc
    public override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        handle(event: event)
    }

    @objc
    public override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        handle(event: event)
    }

    private func handle(event: UIEvent) {
        var hasValidTouch = false
        if let allTouches = event.allTouches {
            for touch in allTouches {
                switch touch.phase {
                case .began, .moved, .stationary:
                    hasValidTouch = true
                default:
                    break
                }
            }
        }

        if hasValidTouch {
            switch self.state {
            case .possible:
                self.state = .began
            case .began, .changed:
                self.state = .changed
            default:
                self.state = .failed
            }
        } else {
            switch self.state {
            case .began, .changed:
                self.state = .ended
            default:
                self.state = .failed
            }
        }
    }
}
