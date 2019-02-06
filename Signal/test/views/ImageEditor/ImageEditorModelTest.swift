//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import XCTest
@testable import Signal
@testable import SignalMessaging

class ImageEditorModelTest: SignalBaseTest {

//    override func setUp() {
//        super.setUp()
//    }
//
//    override func tearDown() {
//        // Put teardown code here. This method is called after the invocation of each test method in the class.
//        super.tearDown()
//    }

    func testImageEditorTransform0() {
        let imageSizePixels = CGSize(width: 200, height: 300)
        let outputSizePixels = CGSize(width: 200, height: 300)
        let unitTranslation = CGPoint.zero
        let rotationRadians: CGFloat = 0
        let scaling: CGFloat = 1
        let transform = ImageEditorTransform(outputSizePixels: outputSizePixels, unitTranslation: unitTranslation, rotationRadians: rotationRadians, scaling: scaling)

        let viewSize = outputSizePixels
        let imageFrame = ImageEditorCanvasView.imageFrame(forViewSize: viewSize, imageSize: imageSizePixels, transform: transform)
        let affineTransform = transform.affineTransform(viewSize: viewSize)

        XCTAssertEqual(0.0, imageFrame.topLeft.applying(affineTransform).x, accuracy: 0.1)
        XCTAssertEqual(0.0, imageFrame.topLeft.applying(affineTransform).y, accuracy: 0.1)
        XCTAssertEqual(100.0, imageFrame.center.applying(affineTransform).x, accuracy: 0.1)
        XCTAssertEqual(150.0, imageFrame.center.applying(affineTransform).y, accuracy: 0.1)
        XCTAssertEqual(200.0, imageFrame.bottomRight.applying(affineTransform).x, accuracy: 0.1)
        XCTAssertEqual(300.0, imageFrame.bottomRight.applying(affineTransform).y, accuracy: 0.1)
    }

    func testImageEditorTransform1() {
        let imageSizePixels = CGSize(width: 864, height: 1536)
        let outputSizePixels = CGSize(width: 432, height: 768)
        let unitTranslation = CGPoint(x: +0.5, y: -0.5)
        let rotationRadians: CGFloat = 0
        let scaling: CGFloat = 2
        let transform = ImageEditorTransform(outputSizePixels: outputSizePixels, unitTranslation: unitTranslation, rotationRadians: rotationRadians, scaling: scaling)

        let viewSize = CGSize(width: 335, height: 595)
        let imageFrame = ImageEditorCanvasView.imageFrame(forViewSize: viewSize, imageSize: imageSizePixels, transform: transform)
        let affineTransform = transform.affineTransform(viewSize: viewSize)

        XCTAssertEqual(0.0, imageFrame.topLeft.applying(affineTransform).x, accuracy: 0.1)
        XCTAssertEqual(0.0, imageFrame.topLeft.applying(affineTransform).y, accuracy: 0.1)
        XCTAssertEqual(100.0, imageFrame.center.applying(affineTransform).x, accuracy: 0.1)
        XCTAssertEqual(150.0, imageFrame.center.applying(affineTransform).y, accuracy: 0.1)
        XCTAssertEqual(200.0, imageFrame.bottomRight.applying(affineTransform).x, accuracy: 0.1)
        XCTAssertEqual(300.0, imageFrame.bottomRight.applying(affineTransform).y, accuracy: 0.1)
    }

    func testAffineTransformComposition() {
        XCTAssertEqual(+20.0, CGPoint.zero.applying(CGAffineTransform.translate(CGPoint(x: 20, y: 30)).scale(5)).x, accuracy: 0.1)
        XCTAssertEqual(+30.0, CGPoint.zero.applying(CGAffineTransform.translate(CGPoint(x: 20, y: 30)).scale(5)).y, accuracy: 0.1)
        XCTAssertEqual(+100.0, CGPoint.zero.applying(CGAffineTransform.scale(5).translate(CGPoint(x: 20, y: 30))).x, accuracy: 0.1)
        XCTAssertEqual(+150.0, CGPoint.zero.applying(CGAffineTransform.scale(5).translate(CGPoint(x: 20, y: 30))).y, accuracy: 0.1)

        XCTAssertEqual(+20.0, CGPoint.zero.applying(CGAffineTransform.translate(CGPoint(x: 20, y: 30)).rotate(CGFloat.halfPi).scale(5)).x, accuracy: 0.1)
        XCTAssertEqual(+30.0, CGPoint.zero.applying(CGAffineTransform.translate(CGPoint(x: 20, y: 30)).rotate(CGFloat.halfPi).scale(5)).y, accuracy: 0.1)
        XCTAssertEqual(-150.0, CGPoint.zero.applying(CGAffineTransform.scale(5).rotate(CGFloat.halfPi).translate(CGPoint(x: 20, y: 30))).x, accuracy: 0.1)
        XCTAssertEqual(+100.0, CGPoint.zero.applying(CGAffineTransform.scale(5).rotate(CGFloat.halfPi).translate(CGPoint(x: 20, y: 30))).y, accuracy: 0.1)

        XCTAssertEqual(+25.0, CGPoint.unit.applying(CGAffineTransform.translate(CGPoint(x: 20, y: 30)).scale(5)).x, accuracy: 0.1)
        XCTAssertEqual(+35.0, CGPoint.unit.applying(CGAffineTransform.translate(CGPoint(x: 20, y: 30)).scale(5)).y, accuracy: 0.1)
        XCTAssertEqual(+105.0, CGPoint.unit.applying(CGAffineTransform.scale(5).translate(CGPoint(x: 20, y: 30))).x, accuracy: 0.1)
        XCTAssertEqual(+155.0, CGPoint.unit.applying(CGAffineTransform.scale(5).translate(CGPoint(x: 20, y: 30))).y, accuracy: 0.1)

        XCTAssertEqual(+15.0, CGPoint.unit.applying(CGAffineTransform.translate(CGPoint(x: 20, y: 30)).rotate(CGFloat.halfPi).scale(5)).x, accuracy: 0.1)
        XCTAssertEqual(+35.0, CGPoint.unit.applying(CGAffineTransform.translate(CGPoint(x: 20, y: 30)).rotate(CGFloat.halfPi).scale(5)).y, accuracy: 0.1)
        XCTAssertEqual(-155.0, CGPoint.unit.applying(CGAffineTransform.scale(5).rotate(CGFloat.halfPi).translate(CGPoint(x: 20, y: 30))).x, accuracy: 0.1)
        XCTAssertEqual(+105.0, CGPoint.unit.applying(CGAffineTransform.scale(5).rotate(CGFloat.halfPi).translate(CGPoint(x: 20, y: 30))).y, accuracy: 0.1)
    }
}
