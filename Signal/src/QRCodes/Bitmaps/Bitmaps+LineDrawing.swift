//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension Bitmaps {
    /// A drawing composed of a rectilinear series of line segments.
    ///
    /// Grid drawings have origin at the bottom-left, matching the default
    /// CoreGraphics context orientation.
    struct GridDrawing: Equatable {
        struct Segment: Hashable, Equatable, CustomDebugStringConvertible {
            enum Dimension: Equatable {
                case vertical
                case horizontal
            }

            let dimension: Dimension
            let start: Point
            let length: Int

            /// Create a new segment.
            ///
            /// - Parameter length
            /// If this value is equal to one, the start and end of the segment
            /// are the same point.
            init(dimension: Dimension, start: Point, length: Int) {
                self.dimension = dimension
                self.start = start
                self.length = length
            }

            var debugDescription: String {
                return "\n{ \(dimension), \(start), \(length) }"
            }

            /// The end of the segment.
            var end: Point {
                return start(offsetBy: length - 1)
            }

            /// The start of the segment offset by the given amount in the
            /// segment's dimension.
            func start(offsetBy offset: Int) -> Point {
                switch dimension {
                case .horizontal:
                    return Point(x: start.x + offset, y: start.y)
                case .vertical:
                    return Point(x: start.x, y: start.y + offset)
                }
            }
        }

        /// The width of the drawing, in pixels.
        let width: Int

        /// The height of the drawing, in pixels.
        let height: Int

        /// The segments comprising the drawing.
        let segments: Set<Segment>
    }
}

extension Bitmaps.Image {
    private typealias Segment = Bitmaps.GridDrawing.Segment
    private typealias Point = Bitmaps.Point

    /// Merges adjacent pixels in the bitmap to create a line drawing.
    ///
    /// Specifically, returns a set of segments such that:
    /// - For a horizontal segment with start at `{X,Y}` and length `N` all
    ///   pixels in the inclusive range `{X,Y}:{X+N,Y}` are visible.
    /// - For a vertical segment with start at `{X,Y}` and length `N` all pixels
    ///   in the inclusive range `{X,Y}:{X,Y+N}` are visible.
    ///
    /// - Parameter deadzone
    /// A region that should be left clear, defined by the circle inscribed in
    /// the given rect.
    func gridDrawingByMergingAdjacentPixels(
        deadzone: Bitmaps.Rect
    ) -> Bitmaps.GridDrawing {
        var segments: [Segment] = []

        for row in 0..<height {
            segments.append(contentsOf: mergedAdjacentPixelsInDimension(
                dimension: .horizontal,
                dimensionIteration: 0...width,
                currentPointBlock: { i in Point(x: i, y: row) },
                pointInDeadzoneBlock: { p in deadzone.inscribedCircleContains(p) }
            ))
        }

        for column in 0..<width {
            segments.append(contentsOf: mergedAdjacentPixelsInDimension(
                dimension: .vertical,
                dimensionIteration: 0...height,
                currentPointBlock: { i in Point(x: column, y: i) },
                pointInDeadzoneBlock: { p in deadzone.inscribedCircleContains(p) }
            ))
        }

        return Bitmaps.GridDrawing(
            width: width,
            height: height,
            segments: Set(segments)
        )
    }

    private func mergedAdjacentPixelsInDimension(
        dimension: Segment.Dimension,
        dimensionIteration: ClosedRange<Int>,
        currentPointBlock: (_ iterationPoint: Int) -> Point,
        pointInDeadzoneBlock: (_ point: Point) -> Bool
    ) -> [Segment] {
        var newSegments: [Segment] = []
        var currentSegmentStart: Point?
        var currentSegmentLength: Int?

        for i in dimensionIteration {
            let currentPoint: Point = currentPointBlock(i)

            if
                hasVisiblePixel(at: currentPoint),
                !pointInDeadzoneBlock(currentPoint)
            {
                if currentSegmentStart != nil {
                    // Extend the current segment.
                    currentSegmentLength! += 1
                } else {
                    // Start a new segment.
                    currentSegmentStart = currentPoint
                    currentSegmentLength = 1
                }
            } else if let finishedSegmentStart = currentSegmentStart {
                // End the current segment. This can never be the first iteration.
                newSegments.append(Segment(
                    dimension: dimension,
                    start: finishedSegmentStart,
                    length: currentSegmentLength!
                ))

                currentSegmentStart = nil
                currentSegmentLength = nil
            }
        }

        return newSegments
    }
}
