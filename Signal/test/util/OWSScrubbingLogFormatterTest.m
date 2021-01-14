//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "OWSScrubbingLogFormatter.h"
#import "SignalBaseTest.h"
#import <SignalCoreKit/NSData+OWS.h>
#import <SignalCoreKit/Randomness.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/TSGroupThread.h>

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

- (void)testDataScrubbed_preformatted
{
    NSDictionary<NSString *, NSString *> *expectedOutputs = @{
        @"<01>" : @"[ REDACTED_DATA:01... ]",
        @"<0123>" : @"[ REDACTED_DATA:01... ]",
        @"<012345>" : @"[ REDACTED_DATA:01... ]",
        @"<01234567>" : @"[ REDACTED_DATA:01... ]",
        @"<01234567 89>" : @"[ REDACTED_DATA:01... ]",
        @"<01234567 89a2>" : @"[ REDACTED_DATA:01... ]",
        @"<01234567 89a23d>" : @"[ REDACTED_DATA:01... ]",
        @"<01234567 89a23def>" : @"[ REDACTED_DATA:01... ]",
        @"<01234567 89a23def 23>" : @"[ REDACTED_DATA:01... ]",
        @"<01234567 89a23def 2323>" : @"[ REDACTED_DATA:01... ]",
        @"<01234567 89a23def 232345>" : @"[ REDACTED_DATA:01... ]",
        @"<01234567 89a23def 23234567>" : @"[ REDACTED_DATA:01... ]",
        @"<01234567 89a23def 23234567 89>" : @"[ REDACTED_DATA:01... ]",
        @"<01234567 89a23def 23234567 89ab>" : @"[ REDACTED_DATA:01... ]",
        @"<01234567 89a23def 23234567 89ab12>" : @"[ REDACTED_DATA:01... ]",
        @"<01234567 89a23def 23234567 89ab1234>" : @"[ REDACTED_DATA:01... ]",
        @"{length = 32, bytes = 0xaa}" : @"[ REDACTED_DATA:aa... ]",
        @"{length = 32, bytes = 0xaaaaaaaa}" : @"[ REDACTED_DATA:aa... ]",
        @"{length = 32, bytes = 0xff}" : @"[ REDACTED_DATA:ff... ]",
        @"{length = 32, bytes = 0xffff}" : @"[ REDACTED_DATA:ff... ]",
        @"{length = 32, bytes = 0x00}" : @"[ REDACTED_DATA:00... ]",
        @"{length = 32, bytes = 0x0000}" : @"[ REDACTED_DATA:00... ]",
        @"{length = 32, bytes = 0x99}" : @"[ REDACTED_DATA:99... ]",
        @"{length = 32, bytes = 0x999999}" : @"[ REDACTED_DATA:99... ]",
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

- (void)testIOS13AndHigherDataScrubbed
{
    NSDictionary<NSString *, NSString *> *expectedOutputs = @{
        @"{length = 32, bytes = 0x01}" : @"[ REDACTED_DATA:01... ]",
        @"{length = 32, bytes = 0x0123}" : @"[ REDACTED_DATA:01... ]",
        @"{length = 32, bytes = 0x012345}" : @"[ REDACTED_DATA:01... ]",
        @"{length = 32, bytes = 0x01234567}" : @"[ REDACTED_DATA:01... ]",
        @"{length = 32, bytes = 0x0123456789}" : @"[ REDACTED_DATA:01... ]",
        @"{length = 32, bytes = 0x0123456789a2}" : @"[ REDACTED_DATA:01... ]",
        @"{length = 32, bytes = 0x0123456789a23d}" : @"[ REDACTED_DATA:01... ]",
        @"{length = 32, bytes = 0x0123456789a23def}" : @"[ REDACTED_DATA:01... ]",
        @"{length = 32, bytes = 0x0123456789a23def23}" : @"[ REDACTED_DATA:01... ]",
        @"{length = 32, bytes = 0x0123456789a23def2323}" : @"[ REDACTED_DATA:01... ]",
        @"{length = 32, bytes = 0x0123456789a23def232345}" : @"[ REDACTED_DATA:01... ]",
        @"{length = 32, bytes = 0x0123456789a23def23234567}" : @"[ REDACTED_DATA:01... ]",
        @"{length = 32, bytes = 0x0123456789a23def2323456789}" : @"[ REDACTED_DATA:01... ]",
        @"{length = 32, bytes = 0x0123456789a23def2323456789ab}" : @"[ REDACTED_DATA:01... ]",
        @"{length = 32, bytes = 0x0123456789a23def2323456789ab12}" : @"[ REDACTED_DATA:01... ]",
        @"{length = 32, bytes = 0x0123456789a23def2323456789ab1234}" : @"[ REDACTED_DATA:01... ]",
        @"{length = 32, bytes = 0xaa}" : @"[ REDACTED_DATA:aa... ]",
        @"{length = 32, bytes = 0xaaaaaaaa}" : @"[ REDACTED_DATA:aa... ]",
        @"{length = 32, bytes = 0xff}" : @"[ REDACTED_DATA:ff... ]",
        @"{length = 32, bytes = 0xffff}" : @"[ REDACTED_DATA:ff... ]",
        @"{length = 32, bytes = 0x00}" : @"[ REDACTED_DATA:00... ]",
        @"{length = 32, bytes = 0x0000}" : @"[ REDACTED_DATA:00... ]",
        @"{length = 32, bytes = 0x99}" : @"[ REDACTED_DATA:99... ]",
        @"{length = 32, bytes = 0x999999}" : @"[ REDACTED_DATA:99... ]",
        @"My data is: {length = 32, bytes = 0x0123456789a23def2323456789ab1223}" :
            @"My data is: [ REDACTED_DATA:01... ]",
        @"My data is {length = 32, bytes = 0x1234567089a23def2323456789ab1223} their data is {length = 16, bytes = "
        @"0x8765432189ab1234}" : @"My data is [ REDACTED_DATA:12... ] their data is [ REDACTED_DATA:87... ]"
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

- (void)testDataScrubbed_lazyFormatted
{
    NSDictionary<NSData *, NSString *> *expectedOutputs = @{
        [NSData dataFromHexString:@"01"] : @"[ REDACTED_DATA:01... ]",
        [NSData dataFromHexString:@"0123"] : @"[ REDACTED_DATA:01... ]",
        [NSData dataFromHexString:@"012345"] : @"[ REDACTED_DATA:01... ]",
        [NSData dataFromHexString:@"01234567"] : @"[ REDACTED_DATA:01... ]",
        [NSData dataFromHexString:@"0123456789"] : @"[ REDACTED_DATA:01... ]",
        [NSData dataFromHexString:@"0123456789a2"] : @"[ REDACTED_DATA:01... ]",
        [NSData dataFromHexString:@"0123456789a23d"] : @"[ REDACTED_DATA:01... ]",
        [NSData dataFromHexString:@"0123456789a23def"] : @"[ REDACTED_DATA:01... ]",
        [NSData dataFromHexString:@"0123456789a23def23"] : @"[ REDACTED_DATA:01... ]",
        [NSData dataFromHexString:@"0123456789a23def2323"] : @"[ REDACTED_DATA:01... ]",
        [NSData dataFromHexString:@"0123456789a23def232345"] : @"[ REDACTED_DATA:01... ]",
        [NSData dataFromHexString:@"0123456789a23def23234567"] : @"[ REDACTED_DATA:01... ]",
        [NSData dataFromHexString:@"0123456789a23def2323456789"] : @"[ REDACTED_DATA:01... ]",
        [NSData dataFromHexString:@"0123456789a23def2323456789ab"] : @"[ REDACTED_DATA:01... ]",
        [NSData dataFromHexString:@"0123456789a23def2323456789ab12"] : @"[ REDACTED_DATA:01... ]",
        [NSData dataFromHexString:@"0123456789a23def2323456789ab1234"] : @"[ REDACTED_DATA:01... ]",
        [NSData dataFromHexString:@"ff"] : @"[ REDACTED_DATA:ff... ]",
        [NSData dataFromHexString:@"ffffff"] : @"[ REDACTED_DATA:ff... ]",
        [NSData dataFromHexString:@"aa"] : @"[ REDACTED_DATA:aa... ]",
        [NSData dataFromHexString:@"aaaaaa"] : @"[ REDACTED_DATA:aa... ]",
        [NSData dataFromHexString:@"00"] : @"[ REDACTED_DATA:00... ]",
        [NSData dataFromHexString:@"00000000"] : @"[ REDACTED_DATA:00... ]",
        [NSData dataFromHexString:@"99"] : @"[ REDACTED_DATA:99... ]",
        [NSData dataFromHexString:@"999999"] : @"[ REDACTED_DATA:99... ]",
    };

    OWSScrubbingLogFormatter *formatter = [OWSScrubbingLogFormatter new];

    // Other formatters add a dynamic date prefix to log lines. We truncate that when comparing our expected output.
    NSUInteger datePrefixLength = [formatter formatLogMessage:[self messageWithString:@""]].length;

    for (NSData *rawData in expectedOutputs) {

        NSString *rawActual = [formatter formatLogMessage:[self messageWithString:rawData.description]];

        // strip out dynamic date portion of log line
        NSString *actual =
            [rawActual substringWithRange:NSMakeRange(datePrefixLength, rawActual.length - datePrefixLength)];

        NSString *expected = expectedOutputs[rawData];

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

- (void)testUUIDsScrubbed_Random
{
    NSArray<NSString *> *uuidStrings = @[
                                         NSUUID.UUID.UUIDString,
                                         NSUUID.UUID.UUIDString,
                                         NSUUID.UUID.UUIDString,
                                         NSUUID.UUID.UUIDString,
                                         ];
    
    for (NSString *uuidString in uuidStrings) {
        OWSScrubbingLogFormatter *formatter = [OWSScrubbingLogFormatter new];
        NSString *messageText = [NSString stringWithFormat:@"My UUID is %@", uuidString];
        NSString *actual = [formatter formatLogMessage:[self messageWithString:messageText]];
        NSRange redactedRange = [actual rangeOfString:@"My UUID is [ REDACTED_UUID:xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxx"];
        XCTAssertNotEqual(NSNotFound, redactedRange.location, "Failed to redact UUID string: %@", uuidString);
        
        NSRange uuidRange = [actual rangeOfString:uuidString];
        XCTAssertEqual(NSNotFound, uuidRange.location, "Failed to redact UUID string: %@", uuidString);
    }
}

- (void)testUUIDsScrubbed_Specific
{
    NSString *uuidString = @"BAF1768C-2A25-4D8F-83B7-A89C59C98748";
    OWSScrubbingLogFormatter *formatter = [OWSScrubbingLogFormatter new];
    NSString *messageText = [NSString stringWithFormat:@"My UUID is %@", uuidString];
    NSString *actual = [formatter formatLogMessage:[self messageWithString:messageText]];
    OWSLogVerbose(@"actual: %@", actual);
    NSRange redactedRange = [actual rangeOfString:@"My UUID is [ REDACTED_UUID:xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxx48 ]"];
    XCTAssertNotEqual(NSNotFound, redactedRange.location, "Failed to redact UUID string: %@", uuidString);
    
    NSRange uuidRange = [actual rangeOfString:uuidString];
    XCTAssertEqual(NSNotFound, uuidRange.location, "Failed to redact UUID string: %@", uuidString);
}

@end

NS_ASSUME_NONNULL_END
