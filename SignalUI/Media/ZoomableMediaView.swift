//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import PureLayout
import SignalServiceKit

public class ZoomableMediaView: UIScrollView {
    private let mediaView: UIView
    private let singleTapGestureBlock: () -> Void

    private var mediaViewBottomConstraint: NSLayoutConstraint!
    private var mediaViewLeadingConstraint: NSLayoutConstraint!
    private var mediaViewTopConstraint: NSLayoutConstraint!
    private var mediaViewTrailingConstraint: NSLayoutConstraint!

    private var lastKnownSafeAreaSize: CGSize

    public init(mediaView: UIView, onSingleTap: @escaping () -> Void = {}) {
        self.mediaView = mediaView
        self.singleTapGestureBlock = onSingleTap
        self.lastKnownSafeAreaSize = .zero
        super.init(frame: .zero)

        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        decelerationRate = .fast
        translatesAutoresizingMaskIntoConstraints = false

        addSubview(mediaView)
        mediaViewLeadingConstraint = mediaView.autoPinEdge(toSuperviewEdge: .leading)
        mediaViewTopConstraint = mediaView.autoPinEdge(toSuperviewEdge: .top)
        mediaViewTrailingConstraint = mediaView.autoPinEdge(toSuperviewEdge: .trailing)
        mediaViewBottomConstraint = mediaView.autoPinEdge(toSuperviewEdge: .bottom)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)

        let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap))
        singleTap.require(toFail: doubleTap)
        addGestureRecognizer(singleTap)
    }

    public required init?(coder: NSCoder) {
        owsFail("Not implemented!")
    }

    // MARK: -

    @objc
    private func handleDoubleTap(_ gestureRecognizer: UIGestureRecognizer) {
        guard zoomScale == minimumZoomScale else {
            // If already zoomed in at all, zoom out all the way.
            zoomOut(animated: true)
            return
        }

        let doubleTapZoomScale: CGFloat = 2

        let zoomWidth = width / doubleTapZoomScale
        let zoomHeight = height / doubleTapZoomScale

        // center zoom rect around tapLocation
        let tapLocation = gestureRecognizer.location(in: self)
        let zoomX = max(0, tapLocation.x - zoomWidth / 2)
        let zoomY = max(0, tapLocation.y - zoomHeight / 2)
        let zoomRect = CGRect(x: zoomX, y: zoomY, width: zoomWidth, height: zoomHeight)

        let translatedRect = mediaView.convert(zoomRect, from: self)
        zoom(to: translatedRect, animated: true)
    }

    @objc
    private func handleSingleTap() {
        singleTapGestureBlock()
    }

    // MARK: -

    public func updateZoomScaleForLayout() {
        let scrollViewSize = bounds.size

        // We want a default layout that...
        //
        // * Has the media visually centered.
        // * The media content should be zoomed to just barely fit by default,
        //   regardless of the content size.
        // * We should be able to safely zoom.
        // * The "min zoom scale" should satisfy the requirements above.
        // * The user should be able to scale in 4x.
        //
        // We use constraint-based layout and adjust
        // UIScrollView.minimumZoomScale, etc.

        // Determine the media's aspect ratio.
        //
        // * mediaView.intrinsicContentSize is most accurate, but
        //   may not be available yet for media that is loaded async.
        // * The self.image.size should always be available if the
        //   media is valid.
        let mediaSize: CGSize
        let mediaIntrinsicSize = mediaView.intrinsicContentSize
        if mediaIntrinsicSize.width > 0, mediaIntrinsicSize.height > 0 {
            mediaSize = mediaIntrinsicSize
        } else if
            let imageView = mediaView as? UIImageView,
            let image = imageView.image,
            image.size.width > 0,
            image.size.height > 0
        {
            mediaSize = image.size
        } else {
            // We're not sure how big the media is, so make it the same size as
            // the scroll view.
            mediaSize = scrollViewSize
        }

        // Center the media view in the scroll view.
        let mediaViewSize = mediaView.frame.size
        let yOffset = max(0, (bounds.height - mediaViewSize.height) / 2)
        let xOffset = max(0, (bounds.width - mediaViewSize.width) / 2)
        mediaViewTopConstraint.constant = yOffset
        mediaViewBottomConstraint.constant = yOffset
        mediaViewLeadingConstraint.constant = xOffset
        mediaViewTrailingConstraint.constant = -xOffset

        // Find minScale for .scaleAspectFit-style layout.
        let scaleWidth = scrollViewSize.width / mediaSize.width
        let scaleHeight = scrollViewSize.height / mediaSize.height
        let minScale = min(scaleWidth, scaleHeight)
        let maxScale = minScale * 8

        minimumZoomScale = minScale
        maximumZoomScale = maxScale

        if zoomScale < minScale {
            zoomScale = minScale
        } else if zoomScale > maxScale {
            zoomScale = maxScale
        }

        // In iOS multi-tasking, the size of root view (and hence the scroll view)
        // is set later, after viewWillAppear, etc.  Therefore we need to reset the
        // zoomScale to the default whenever the scrollView width changes.
        let currentSafeAreaSize = safeAreaLayoutGuide.layoutFrame.size
        if !(currentSafeAreaSize - lastKnownSafeAreaSize).asPoint.fuzzyEquals(.zero, tolerance: 0.001) {
            zoomScale = minimumZoomScale
        }
        lastKnownSafeAreaSize = currentSafeAreaSize
    }

    public func zoomOut(animated: Bool) {
        guard zoomScale != minimumZoomScale else { return }
        setZoomScale(minimumZoomScale, animated: animated)
    }
}
