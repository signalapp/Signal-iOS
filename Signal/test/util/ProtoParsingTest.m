//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "SSKProto.pb.h"
#import <XCTest/XCTest.h>

@interface ProtoParsingTest : XCTestCase

@end

#pragma mark -

@implementation ProtoParsingTest

- (void)testProtoParsing_nil
{
    SSKProtoEnvelope *_Nullable envelope = [SSKProtoEnvelope parseFromData:nil];
    XCTAssertNotNil(envelope);
}

- (void)testProtoParsing_empty
{
    NSData *data = [NSData new];
    SSKProtoEnvelope *_Nullable envelope = [SSKProtoEnvelope parseFromData:data];
    XCTAssertNotNil(envelope);
}

- (void)testProtoParsing_wrong1
{
    @try {
        NSData *data = [@"test" dataUsingEncoding:NSUTF8StringEncoding];
        [SSKProtoEnvelope parseFromData:data];
        XCTFail(@"Missing expected exception");
    } @catch (NSException *exception) {
        // Exception is expected.
        NSLog(@"Caught expected exception: %@", [exception class]);
    }
}

@end
