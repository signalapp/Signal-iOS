//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import XCTest
@testable import Signal

class ImageCacheTest: SignalBaseTest {

    var imageCache: ImageCache!

    let firstVariation = UIImage()
    let secondVariation = UIImage()
    let otherImage = UIImage()

    let cacheKey1 = "cache-key-1" as NSString
    let cacheKey2 = "cache-key-2" as NSString

    override func setUp() {
        super.setUp()
         self.imageCache = ImageCache()
        imageCache.setImage(firstVariation, forKey: cacheKey1, diameter: 100)
        imageCache.setImage(secondVariation, forKey: cacheKey1, diameter: 200)
        imageCache.setImage(otherImage, forKey: cacheKey2, diameter: 100)
    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    func testSetGet() {
        XCTAssertEqual(firstVariation, imageCache.image(forKey: cacheKey1, diameter: 100))
        XCTAssertEqual(secondVariation, imageCache.image(forKey: cacheKey1, diameter: 200))
        XCTAssertNotEqual(secondVariation, imageCache.image(forKey: cacheKey1, diameter: 100))
        XCTAssertEqual(otherImage, imageCache.image(forKey: cacheKey2, diameter: 100))
        XCTAssertNil(imageCache.image(forKey: cacheKey2, diameter: 200))
    }

    func testRemoveAllForKey() {
        // sanity check
        XCTAssertEqual(firstVariation, imageCache.image(forKey: cacheKey1, diameter: 100))
        XCTAssertEqual(otherImage, imageCache.image(forKey: cacheKey2, diameter: 100))

        imageCache.removeAllImages(forKey: cacheKey1)

        XCTAssertNil(imageCache.image(forKey: cacheKey1, diameter: 100))
        XCTAssertNil(imageCache.image(forKey: cacheKey1, diameter: 200))
        XCTAssertEqual(otherImage, imageCache.image(forKey: cacheKey2, diameter: 100))
    }

    func testRemoveAll() {
        XCTAssertEqual(firstVariation, imageCache.image(forKey: cacheKey1, diameter: 100))

        imageCache.removeAllImages()

        XCTAssertNil(imageCache.image(forKey: cacheKey1, diameter: 100))
        XCTAssertNil(imageCache.image(forKey: cacheKey1, diameter: 200))
        XCTAssertNil(imageCache.image(forKey: cacheKey2, diameter: 100))
    }
}
