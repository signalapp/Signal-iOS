//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <XCTest/XCTest.h>

@interface ProtoParsingTest : XCTestCase

@end

#pragma mark -

@implementation ProtoParsingTest

- (void)testProtoParsing_empty
{
    NSData *data = [NSData new];
    NSError *error;
    SSKProtoEnvelope *_Nullable envelope = [SSKProtoEnvelope parseData:data error:&error];
    XCTAssertNil(envelope);
    XCTAssertNotNil(error);
}

- (void)testProtoParsing_wrong1
{
    NSData *data = [@"test" dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error;
    SSKProtoEnvelope *_Nullable envelope = [SSKProtoEnvelope parseData:data error:&error];
    XCTAssertNil(envelope);
    XCTAssertNotNil(error);
}

@end
