//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

#import "SignalBaseTest.h"
#import <SignalCoreKit/NSData+OWS.h>
#import <SignalCoreKit/Randomness.h>
#import <SignalMessaging/OWSScrubbingLogFormatter.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/TSGroupThread.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSScrubbingLogFormatterTest : SignalBaseTest

@property (nonatomic) NSDate *testDate;
@property (nonatomic) OWSScrubbingLogFormatter *formatter;
@property (nonatomic) NSUInteger datePrefixLength;

@end

@implementation OWSScrubbingLogFormatterTest

- (void)setUp
{
    [super setUp];

    self.testDate = [NSDate new];
    self.formatter = [[OWSScrubbingLogFormatter alloc] init];

    // Other formatters add a dynamic date prefix to log lines. We truncate that when comparing our expected output.
    self.datePrefixLength = [self.formatter formatLogMessage:[self messageWithString:@""]].length;
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
        @"{length = 32, bytes = 0x00010203 44556677 89898989 abcdef01 ... aabbccdd eeff1234 }" :
            @"[ REDACTED_DATA:00... ]",
        @"My data is: <01234567 89a23def 23234567 89ab1223>" : @"My data is: [ REDACTED_DATA:01... ]",
        @"My data is <12345670 89a23def 23234567 89ab1223> their data is <87654321 89ab1234>" :
            @"My data is [ REDACTED_DATA:12... ] their data is [ REDACTED_DATA:87... ]"
    };

    for (NSString *input in expectedOutputs) {
        NSString *rawResult = [self.formatter formatLogMessage:[self messageWithString:input]];
        NSString *result = [self stripDateFromMessage:rawResult];
        NSString *expected = expectedOutputs[input];

        XCTAssertEqualObjects(expected, result, @"Failed redaction: %@", input);
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

    for (NSString *input in expectedOutputs) {
        NSString *rawResult = [self.formatter formatLogMessage:[self messageWithString:input]];
        NSString *result = [self stripDateFromMessage:rawResult];
        NSString *expected = expectedOutputs[input];

        XCTAssertEqualObjects(expected, result, @"Failed redaction: %@", input);
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

    for (NSData *input in expectedOutputs) {
        NSString *rawResult = [self.formatter formatLogMessage:[self messageWithString:input.description]];
        NSString *result = [self stripDateFromMessage:rawResult];
        NSString *expected = expectedOutputs[input];

        XCTAssertEqualObjects(expected, result, @"Failed redaction: %@", input);
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
        NSString *input = [NSString stringWithFormat:@"My phone number is %@", phoneString];
        NSString *result = [self.formatter formatLogMessage:[self messageWithString:input]];

        NSString *expectation = @"My phone number is [ REDACTED_PHONE_NUMBER:xxx234 ]";
        XCTAssertTrue([result containsString:expectation], "Failed to redact phone string: %@", phoneString);
        XCTAssertFalse([result containsString:phoneString], "Failed to redact phone string: %@", phoneString);
    }
}

- (void)testNonPhoneNumberNotScrubbed
{
    NSString *input = @"Some unfiltered string";
    NSString *rawResult = [self.formatter formatLogMessage:[self messageWithString:input]];
    NSString *result = [self stripDateFromMessage:rawResult];
    XCTAssertEqualObjects(input, result, "Shouldn't touch non phone string.");
}

- (void)testIPAddressesScrubbed
{
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
            NSString *input = [messageFormat stringByReplacingOccurrencesOfString:@"%@" withString:ipAddress];
            NSString *rawResult = [self.formatter formatLogMessage:[self messageWithString:input]];
            NSString *result = [self stripDateFromMessage:rawResult];
            NSString *expected = [messageFormat stringByReplacingOccurrencesOfString:@"%@"
                                                                          withString:redactedIPAddress];

            XCTAssertFalse([result containsString:ipAddress], "Failed to redact IP address: %@", input);
            XCTAssertEqualObjects(result, expected, @"Failed redaction: %@", input);
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
        NSString *input = [NSString stringWithFormat:@"My UUID is %@", uuidString];
        NSString *rawResult = [self.formatter formatLogMessage:[self messageWithString:input]];

        NSString *expectation = @"My UUID is [ REDACTED_UUID:xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxx";
        XCTAssertTrue([rawResult containsString:expectation], "Failed to redact UUID string: %@", uuidString);
        XCTAssertFalse([rawResult containsString:uuidString], "Failed to redact UUID string: %@", uuidString);
    }
}

- (void)testUUIDsScrubbed_Specific
{
    NSString *uuidString = @"BAF1768C-2A25-4D8F-83B7-A89C59C98748";
    NSString *input = [NSString stringWithFormat:@"My UUID is %@", uuidString];

    NSString *rawResult = [self.formatter formatLogMessage:[self messageWithString:input]];
    NSString *result = [self stripDateFromMessage:rawResult];

    NSString *expectation = @"My UUID is [ REDACTED_UUID:xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxx748 ]";
    XCTAssertEqualObjects(result, expectation, "Failed to redact UUID string: %@", uuidString);
    XCTAssertFalse([result containsString:uuidString], "Failed to redact UUID string: %@", uuidString);
}

- (void)testTimestampsNotScrubbed
{
    // A couple sample messages from our logs
    NSDictionary<NSString *, NSString *> *expectedOutputs = @{
        // No change:
        @"Sending message: TSOutgoingMessage, timestamp: %llu" : @"Sending message: TSOutgoingMessage, timestamp: %llu",
        // Leave timestamp, but UUID and phone number should be redacted
        @"attempting to send message: TSOutgoingMessage, timestamp: %llu, recipient: <SignalServiceAddress "
        @"phoneNumber: +12345678900, uuid: BAF1768C-2A25-4D8F-83B7-A89C59C98748>" :
            @"attempting to send message: TSOutgoingMessage, timestamp: %llu, recipient: <SignalServiceAddress "
            @"phoneNumber: [ REDACTED_PHONE_NUMBER:xxx900 ], uuid: [ "
            @"REDACTED_UUID:xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxx748 ]>",
    };

    for (NSString *inputFormat in expectedOutputs) {
        uint64_t timestamp = [[NSDate date] ows_millisecondsSince1970];
        NSString *input = [NSString stringWithFormat:inputFormat, timestamp];

        NSString *rawResult = [self.formatter formatLogMessage:[self messageWithString:input]];
        NSString *result = [self stripDateFromMessage:rawResult];

        NSString *expectationFormat = expectedOutputs[inputFormat];
        NSString *expectation = [NSString stringWithFormat:expectationFormat, timestamp];

        XCTAssertEqualObjects(result, expectation);
    }
}

- (void)testLongHexStrings
{
    NSDictionary<NSString *, NSString *> *expectedOutputs = @{
        @"" : @"",
        @"01" : @"01",
        @"0102" : @"0102",
        @"010203" : @"010203",
        @"01020304" : @"01020304",
        @"0102030405" : @"0102030405",
        @"010203040506" : @"010203040506",
        @"01020304050607" : @"[ REDACTED_HEX:...607 ]",
        @"0102030405060708" : @"[ REDACTED_HEX:...708 ]",
        @"010203040506070809" : @"[ REDACTED_HEX:...809 ]",
        @"010203040506070809ab" : @"[ REDACTED_HEX:...9ab ]",
        @"010203040506070809abcd" : @"[ REDACTED_HEX:...bcd ]",
    };

    for (NSString *input in expectedOutputs) {
        NSString *rawResult = [self.formatter formatLogMessage:[self messageWithString:input]];
        NSString *result = [self stripDateFromMessage:rawResult];
        NSString *expected = expectedOutputs[input];

        XCTAssertEqualObjects(expected, result, @"Failed redaction: %@", input);
    }
}

- (NSString *)stripDateFromMessage:(NSString *)rawMessage
{
    return [rawMessage substringFromIndex:self.datePrefixLength];
}

@end

NS_ASSUME_NONNULL_END
