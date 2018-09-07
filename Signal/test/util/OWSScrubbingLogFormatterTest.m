//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSScrubbingLogFormatter.h"
#import "SignalBaseTest.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSScrubbingLogFormatterTest : SignalBaseTest

@property (nonatomic) NSDate *testDate;

@end

@implementation OWSScrubbingLogFormatterTest

- (void)setUp
{
    [super setUp];

    self.testDate = [NSDate new];
}

- (void)tearDown
{
    [super tearDown];
}

- (DDLogMessage *)messageWithString:(NSString *)string
{
    return [[DDLogMessage alloc] initWithMessage:string
                                           level:DDLogLevelInfo
                                            flag:0
                                         context:0
                                            file:@"mock file name"
                                        function:@"mock function name"
                                            line:0
                                             tag:nil
                                         options:0
                                       timestamp:self.testDate];
}

- (void)testDataScrubbed
{
    NSDictionary<NSString *, NSString *> *expectedOutputs = @{
        @"<01234567 89a23def 23234567 89ab1234>" : @"[ REDACTED_DATA:01... ]",
        @"My data is: <01234567 89a23def 23234567 89ab1223>" : @"My data is: [ REDACTED_DATA:01... ]",
        @"My data is <12345670 89a23def 23234567 89ab1223> their data is <87654321 89ab1234>" :
            @"My data is [ REDACTED_DATA:12... ] their data is [ REDACTED_DATA:87... ]"
    };

    OWSScrubbingLogFormatter *formatter = [OWSScrubbingLogFormatter new];

    // Other formatters add a dynamic date prefix to log lines. We truncate that when comparing our expected output.
    NSUInteger datePrefixLength = [formatter formatLogMessage:[self messageWithString:@""]].length;

    for (NSString *input in expectedOutputs) {

        NSString *rawActual = [formatter formatLogMessage:[self messageWithString:input]];

        // strip out dynamic date portion of log line
        NSString *actual =
            [rawActual substringWithRange:NSMakeRange(datePrefixLength, rawActual.length - datePrefixLength)];

        NSString *expected = expectedOutputs[input];

        XCTAssertEqualObjects(expected, actual);
    }
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

- (void)testNonPhoneNumberNotScrubbed
{
    OWSScrubbingLogFormatter *formatter = [OWSScrubbingLogFormatter new];
    NSString *actual =
        [formatter formatLogMessage:[self messageWithString:[NSString stringWithFormat:@"Some unfiltered string"]]];

    NSRange redactedRange = [actual rangeOfString:@"Some unfiltered string"];
    XCTAssertNotEqual(NSNotFound, redactedRange.location, "Shouldn't touch non phone string.");
}

- (void)testIPAddressesScrubbed
{
    id<DDLogFormatter> scrubbingFormatter = [OWSScrubbingLogFormatter new];
    id<DDLogFormatter> defaultFormatter = [DDLogFileFormatterDefault new];

    NSDictionary<NSString *, NSString *> *valueMap = @{
        @"0.0.0.0" : @"[ REDACTED_IPV4_ADDRESS:...0 ]",
        @"127.0.0.1" : @"[ REDACTED_IPV4_ADDRESS:...1 ]",
        @"255.255.255.255" : @"[ REDACTED_IPV4_ADDRESS:...255 ]",
        @"1.2.3.4" : @"[ REDACTED_IPV4_ADDRESS:...4 ]",
    };
    NSArray<NSString *> *messageFormats = @[
        @"a%@b",
        @"http://%@",
        @"http://%@/",
        @"%@ and %@ and %@",
        @"%@",
        @"%@ %@",
        @"no ip address!",
        @"",
    ];

    for (NSString *ipAddress in valueMap) {
        NSString *redactedIPAddress = valueMap[ipAddress];

        for (NSString *messageFormat in messageFormats) {
            NSString *message = [messageFormat stringByReplacingOccurrencesOfString:@"%@" withString:ipAddress];

            NSString *unredactedMessage = [defaultFormatter formatLogMessage:[self messageWithString:messageFormat]];
            NSString *expectedRedactedMessage = [defaultFormatter
                formatLogMessage:[self messageWithString:[messageFormat
                                                             stringByReplacingOccurrencesOfString:@"%@"
                                                                                       withString:redactedIPAddress]]];
            NSString *redactedMessage = [scrubbingFormatter formatLogMessage:[self messageWithString:message]];

            XCTAssertEqualObjects(
                expectedRedactedMessage, redactedMessage, @"Scrubbing failed for message: %@", unredactedMessage);

            NSRange ipAddressRange = [redactedMessage rangeOfString:ipAddress];
            XCTAssertEqual(NSNotFound, ipAddressRange.location, "Failed to redact IP address: %@", unredactedMessage);
        }
    }
}

@end

NS_ASSUME_NONNULL_END
