//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSDeviceProvisioningURLParser.h"
#import "SignalBaseTest.h"
#import <SignalServiceKit/NSData+OWS.h>

@interface OWSDeviceProvisioningURLParserTest : SignalBaseTest

@end

@implementation OWSDeviceProvisioningURLParserTest

- (void)testValid
{
    OWSDeviceProvisioningURLParser *parser = [[OWSDeviceProvisioningURLParser alloc] initWithProvisioningURL:@""];
    XCTAssertFalse(parser.isValid);

    parser = [[OWSDeviceProvisioningURLParser alloc] initWithProvisioningURL:@"ts:/?uuid=MTIz"];
    XCTAssertFalse(parser.isValid);

    parser = [[OWSDeviceProvisioningURLParser alloc] initWithProvisioningURL:@"ts:/?pub_key=MTIz"];
    XCTAssertFalse(parser.isValid);

    parser = [[OWSDeviceProvisioningURLParser alloc] initWithProvisioningURL:@"ts:/uuid=asd&pub_key=MTIz"];
    XCTAssertFalse(parser.isValid);

    parser = [[OWSDeviceProvisioningURLParser alloc] initWithProvisioningURL:@"ts:/?uuid=asd&pub_key=MTIz"];
    XCTAssert(parser.isValid);
}

- (void)testPublicKey
{
    OWSDeviceProvisioningURLParser *parser =
        [[OWSDeviceProvisioningURLParser alloc] initWithProvisioningURL:@"ts:/?uuid=asd&pub_key=MTIz"];

    XCTAssertEqualObjects(@"MTIz", [parser.publicKey base64EncodedString]);
}

- (void)testEphemeralDeviceId
{
    OWSDeviceProvisioningURLParser *parser =
        [[OWSDeviceProvisioningURLParser alloc] initWithProvisioningURL:@"ts:/?uuid=asd&pub_key=MTIz"];

    XCTAssertEqualObjects(@"asd", parser.ephemeralDeviceId);
}

@end
