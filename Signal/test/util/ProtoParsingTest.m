//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "SignalBaseTest.h"
#import <SignalCoreKit/NSData+OWS.h>
#import <SignalCoreKit/Randomness.h>
#import <SignalServiceKit/ContactsManagerProtocol.h>
#import <SignalServiceKit/OWSContactsOutputStream.h>
#import <SignalServiceKit/OWSGroupsOutputStream.h>
#import <SignalServiceKit/SignalAccount.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark -

@interface ProtoParsingTest : SignalBaseTest

@end

#pragma mark -

@implementation ProtoParsingTest

- (void)testProtoParsing_empty
{
    NSData *data = [NSData new];
    NSError *error;
    SSKProtoEnvelope *_Nullable envelope = [[SSKProtoEnvelope alloc] initWithSerializedData:data error:&error];
    XCTAssertNil(envelope);
    XCTAssertNotNil(error);
}

- (void)testProtoParsing_wrong1
{
    NSData *data = [@"test" dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error;
    SSKProtoEnvelope *_Nullable envelope = [[SSKProtoEnvelope alloc] initWithSerializedData:data error:&error];
    XCTAssertNil(envelope);
    XCTAssertNotNil(error);
}

@end

NS_ASSUME_NONNULL_END
