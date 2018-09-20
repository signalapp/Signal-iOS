//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "SignalBaseTest.h"
#import <Curve25519Kit/Randomness.h>
#import <SignalServiceKit/ContactsManagerProtocol.h>
#import <SignalServiceKit/NSData+OWS.h>
#import <SignalServiceKit/OWSContactsOutputStream.h>
#import <SignalServiceKit/OWSGroupsOutputStream.h>
#import <SignalServiceKit/SignalAccount.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@class CNContact;

@interface TestContactsManager : NSObject <ContactsManagerProtocol>

@end

#pragma mark -

@implementation TestContactsManager

- (NSString *)displayNameForPhoneIdentifier:(NSString *_Nullable)phoneNumber
{
    return phoneNumber;
}

- (NSArray<SignalAccount *> *)signalAccounts
{
    return @[];
}

- (BOOL)isSystemContact:(NSString *)recipientId
{
    return YES;
}

- (BOOL)isSystemContactWithSignalAccount:(NSString *)recipientId
{
    return YES;
}

- (NSComparisonResult)compareSignalAccount:(SignalAccount *)left withSignalAccount:(SignalAccount *)right
{
    return NSOrderedSame;
}

- (nullable CNContact *)cnContactWithId:(nullable NSString *)contactId
{
    return nil;
}

- (nullable NSData *)avatarDataForCNContactId:(nullable NSString *)contactId
{
    return nil;
}

- (nullable UIImage *)avatarImageForCNContactId:(nullable NSString *)contactId
{
    return nil;
}

@end

#pragma mark -

@interface FakeContact : NSObject

@property (nullable, nonatomic) NSString *firstName;
@property (nullable, nonatomic) NSString *lastName;
@property (nonatomic) NSString *fullName;
@property (nonatomic) NSString *comparableNameFirstLast;
@property (nonatomic) NSString *comparableNameLastFirst;
@property (nonatomic) NSArray<PhoneNumber *> *parsedPhoneNumbers;
@property (nonatomic) NSArray<NSString *> *userTextPhoneNumbers;
@property (nonatomic) NSArray<NSString *> *emails;
@property (nonatomic) NSString *uniqueId;
@property (nonatomic) BOOL isSignalContact;
@property (nonatomic) NSString *cnContactId;

@end

#pragma mark -

@implementation FakeContact

@end

#pragma mark -

@interface ProtoParsingTest : SignalBaseTest

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

- (void)testProtoStreams
{
    NSArray<SignalAccount *> *signalAccounts = @[
        [[SignalAccount alloc] initWithRecipientId:@"+13213214321"],
        [[SignalAccount alloc] initWithRecipientId:@"+13213214322"],
        [[SignalAccount alloc] initWithRecipientId:@"+13213214323"],
    ];
    NSData *_Nullable streamData = [self dataForSyncingContacts:signalAccounts];
    XCTAssertNotNil(streamData);

    XCTAssertEqualObjects(streamData.hexadecimalString,
        @"2c0a0c2b31333231333231343332311209416c69636520426f62220f66616b6520636f6c6f72206e616d6540002c0a0c2b31333231333"
        @"231343332321209416c69636520426f62220f66616b6520636f6c6f72206e616d6540002c0a0c2b31333231333231343332331209416c"
        @"69636520426f62220f66616b6520636f6c6f72206e616d654000");
}

- (nullable NSData *)dataForSyncingContacts:(NSArray<SignalAccount *> *)signalAccounts
{
    TestContactsManager *contactsManager = [TestContactsManager new];
    NSOutputStream *dataOutputStream = [NSOutputStream outputStreamToMemory];
    [dataOutputStream open];
    OWSContactsOutputStream *contactsOutputStream =
        [[OWSContactsOutputStream alloc] initWithOutputStream:dataOutputStream];

    for (SignalAccount *signalAccount in signalAccounts) {
        OWSRecipientIdentity *_Nullable recipientIdentity = nil;
        //        NSData *_Nullable profileKeyData = [Randomness generateRandomBytes:32];
        NSData *_Nullable profileKeyData = nil;
        OWSDisappearingMessagesConfiguration *_Nullable disappearingMessagesConfiguration = nil;
        NSString *_Nullable conversationColorName = @"fake color name";

        FakeContact *fakeContact = [FakeContact new];
        fakeContact.cnContactId = @"123";
        fakeContact.fullName = @"Alice Bob";
        signalAccount.contact = (Contact *)fakeContact;

        [contactsOutputStream writeSignalAccount:signalAccount
                               recipientIdentity:recipientIdentity
                                  profileKeyData:profileKeyData
                                 contactsManager:contactsManager
                           conversationColorName:conversationColorName
               disappearingMessagesConfiguration:disappearingMessagesConfiguration];
    }

    [dataOutputStream close];

    if (contactsOutputStream.hasError) {
        return nil;
    }

    return [dataOutputStream propertyForKey:NSStreamDataWrittenToMemoryStreamKey];
}

@end

NS_ASSUME_NONNULL_END
