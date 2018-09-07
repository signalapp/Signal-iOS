//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "NSData+OWS.h"
#import "OWSAnalytics.h"
#import "SSKBaseTest.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSAnalyticsTests : SSKBaseTest

@end

#pragma mark -

@implementation OWSAnalyticsTests

- (void)testOrderOfMagnitudeOf
{
    XCTAssertEqual(0, [OWSAnalytics orderOfMagnitudeOf:-1]);
    XCTAssertEqual(0, [OWSAnalytics orderOfMagnitudeOf:0]);
    XCTAssertEqual(1, [OWSAnalytics orderOfMagnitudeOf:1]);
    XCTAssertEqual(1, [OWSAnalytics orderOfMagnitudeOf:5]);
    XCTAssertEqual(1, [OWSAnalytics orderOfMagnitudeOf:9]);
    XCTAssertEqual(10, [OWSAnalytics orderOfMagnitudeOf:10]);
    XCTAssertEqual(10, [OWSAnalytics orderOfMagnitudeOf:11]);
    XCTAssertEqual(10, [OWSAnalytics orderOfMagnitudeOf:19]);
    XCTAssertEqual(10, [OWSAnalytics orderOfMagnitudeOf:99]);
    XCTAssertEqual(100, [OWSAnalytics orderOfMagnitudeOf:100]);
    XCTAssertEqual(100, [OWSAnalytics orderOfMagnitudeOf:303]);
    XCTAssertEqual(100, [OWSAnalytics orderOfMagnitudeOf:999]);
    XCTAssertEqual(1000, [OWSAnalytics orderOfMagnitudeOf:1000]);
    XCTAssertEqual(1000, [OWSAnalytics orderOfMagnitudeOf:3030]);
    XCTAssertEqual(10000, [OWSAnalytics orderOfMagnitudeOf:10000]);
    XCTAssertEqual(10000, [OWSAnalytics orderOfMagnitudeOf:30303]);
    XCTAssertEqual(10000, [OWSAnalytics orderOfMagnitudeOf:99999]);
    XCTAssertEqual(100000, [OWSAnalytics orderOfMagnitudeOf:100000]);
    XCTAssertEqual(100000, [OWSAnalytics orderOfMagnitudeOf:303030]);
    XCTAssertEqual(100000, [OWSAnalytics orderOfMagnitudeOf:999999]);
}

@end

NS_ASSUME_NONNULL_END
