//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSSignalServiceProtos.pb.h"
#import <XCTest/XCTest.h>

@interface ProtoParsingTest : XCTestCase

@end

#pragma mark -

@implementation ProtoParsingTest

- (void)testProtoParsing_nil
{
    OWSSignalServiceProtosEnvelope *_Nullable envelope = [OWSSignalServiceProtosEnvelope parseFromData:nil];
    XCTAssertNotNil(envelope);
}

- (void)testProtoParsing_empty
{
    NSData *data = [NSData new];
    OWSSignalServiceProtosEnvelope *_Nullable envelope = [OWSSignalServiceProtosEnvelope parseFromData:data];
    XCTAssertNotNil(envelope);
}

- (void)testProtoParsing_wrong1
{
    @try {
        NSData *data = [@"test" dataUsingEncoding:NSUTF8StringEncoding];
        [OWSSignalServiceProtosEnvelope parseFromData:data];
        XCTFail(@"Missing expected exception");
    } @catch (NSException *exception) {
        // Exception is expected.
        NSLog(@"Caught expected exception: %@", [exception class]);
    }
}

@end
