//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSScrubbingLogFormatter.h"
#import <XCTest/XCTest.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSScrubbingLogFormatterTest : XCTestCase

@end

@implementation OWSScrubbingLogFormatterTest

- (DDLogMessage *)messageWithString:(NSString *)string
{
    return [[DDLogMessage alloc] initWithMessage:string
                                           level:DDLogLevelInfo
                                            flag:0
                                         context:0
                                            file:nil
                                        function:nil
                                            line:0
                                             tag:nil
                                         options:0
                                       timestamp:[NSDate new]];
}

- (void)testPhoneNumbersScrubbed
{
    NSArray<NSString *> *phoneStrings = @[
        @"+13331231234 ",
        @"+4113331231234",
        @"+13331231234 something something +13331231234",
    ];

    for (NSString *phoneString in phoneStrings) {
        OWSScrubbingLogFormatter *formatter = [OWSScrubbingLogFormatter new];
        NSString *messageText = [NSString stringWithFormat:@"My phone number is %@", phoneString];
        NSString *actual = [formatter formatLogMessage:[self messageWithString:messageText]];
        NSRange redactedRange = [actual rangeOfString:@"My phone number is [ REDACTED_PHONE_NUMBER:xxx234 ]"];
        XCTAssertNotEqual(NSNotFound, redactedRange.location, "Failed to redact phone string: %@", phoneString);

        NSRange phoneNumberRange = [actual rangeOfString:phoneString];
        XCTAssertEqual(NSNotFound, phoneNumberRange.location, "Failed to redact phone string: %@", phoneString);
    }
}

- (void)testNonPhonenumberNotScrubbed
{
    OWSScrubbingLogFormatter *formatter = [OWSScrubbingLogFormatter new];
    NSString *actual =
        [formatter formatLogMessage:[self messageWithString:[NSString stringWithFormat:@"Some unfiltered string"]]];

    NSRange redactedRange = [actual rangeOfString:@"Some unfiltered string"];
    XCTAssertNotEqual(NSNotFound, redactedRange.location, "Shouldn't touch non phone string.");
}

@end

NS_ASSUME_NONNULL_END
