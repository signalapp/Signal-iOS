//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
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

@class CNContact;

@interface TestContactsManager : NSObject <ContactsManagerProtocol>

@end

#pragma mark -

@implementation TestContactsManager

- (nonnull NSString *)displayNameForAddress:(SignalServiceAddress *)address
{
    return address.stringForDisplay;
}

- (nonnull NSString *)displayNameForAddress:(SignalServiceAddress *)address
                                transaction:(nonnull YapDatabaseReadTransaction *)transaction
{
    return nil;
}

- (NSString *_Nonnull)displayNameForSignalAccount:(SignalAccount *)signalAccount
{
    return nil;
}

- (NSString *)displayNameForThread:(TSThread *)thread transaction:(SDSAnyReadTransaction *)transaction
{
    return @"Fake Name";
}

- (NSString *)displayNameForThreadWithSneakyTransaction:(TSThread *)thread
{
    return @"Fake Name";
}

- (NSArray<SignalAccount *> *)signalAccounts
{
    return @[];
}

- (BOOL)isSystemContactWithPhoneNumber:(NSString *)phoneNumber
{
    return YES;
}

- (BOOL)isSystemContactWithAddress:(SignalServiceAddress *)address
{
    return YES;
}

- (BOOL)isSystemContactWithSignalAccount:(NSString *)phoneNumber
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
        [[SignalAccount alloc]
            initWithSignalServiceAddress:[[SignalServiceAddress alloc] initWithPhoneNumber:@"+13213214321"]],
        [[SignalAccount alloc]
            initWithSignalServiceAddress:[[SignalServiceAddress alloc]
                                             initWithUuidString:@"31ce1412-9a28-4e6f-b4ee-a25c3179d085"]],
        [[SignalAccount alloc]
            initWithSignalServiceAddress:[[SignalServiceAddress alloc]
                                             initWithUuidString:@"1d4ab045-88fb-4c4e-9f6a-f921124bd529"
                                                    phoneNumber:@"+13213214323"]],
    ];
    NSData *_Nullable streamData = [self dataForSyncingContacts:signalAccounts];
    XCTAssertNotNil(streamData);

    XCTAssertEqualObjects(streamData.hexadecimalString,
        @"2c0a0c2b31333231333231343332311209416c69636520426f62220f66616b6520636f6c6f72206e616d654000441209416c696365204"
        @"26f62220f66616b6520636f6c6f72206e616d6540004a2433314345313431322d394132382d344536462d423445452d41323543333137"
        @"3944303835520a0c2b31333231333231343332331209416c69636520426f62220f66616b6520636f6c6f72206e616d6540004a2431443"
        @"441423034352d383846422d344334452d394636412d463932313132344244353239");
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
