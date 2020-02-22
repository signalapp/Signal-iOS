//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "OWSFakeProfileManager.h"
#import "TSThread.h"
#import <SignalCoreKit/Cryptography.h>
#import <SignalCoreKit/NSData+OWS.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

#ifdef TESTABLE_BUILD

@interface OWSFakeProfileManager ()

@property (nonatomic, readonly) NSMutableDictionary<SignalServiceAddress *, OWSAES256Key *> *profileKeys;
@property (nonatomic, readonly) NSMutableSet<SignalServiceAddress *> *recipientWhitelist;
@property (nonatomic, readonly) NSMutableSet<NSString *> *threadWhitelist;
@property (nonatomic, readonly) OWSAES256Key *localProfileKey;
@property (nonatomic, nullable) NSString *localGivenName;
@property (nonatomic, nullable) NSString *localFamilyName;
@property (nonatomic, nullable) NSString *localFullName;
@property (nonatomic, nullable) NSString *localUsername;
@property (nonatomic, nullable) NSData *localProfileAvatarData;

@end

#pragma mark -

@implementation OWSFakeProfileManager

@synthesize localProfileKey = _localProfileKey;
@synthesize userProfileReadCache = _userProfileReadCache;

- (instancetype)init
{
    self = [super init];
    if (!self) {
        return self;
    }

    _profileKeys = [NSMutableDictionary new];
    _recipientWhitelist = [NSMutableSet new];
    _threadWhitelist = [NSMutableSet new];
    _userProfileReadCache = [UserProfileReadCache new];

    return self;
}

- (OWSAES256Key *)localProfileKey
{
    if (_localProfileKey == nil) {
        _localProfileKey = [OWSAES256Key generateRandomKey];
    }
    return _localProfileKey;
}

- (void)setProfileKeyData:(NSData *)profileKey
               forAddress:(SignalServiceAddress *)address
      wasLocallyInitiated:(BOOL)wasLocallyInitiated
              transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAES256Key *_Nullable key = [OWSAES256Key keyWithData:profileKey];
    OWSAssert(key);
    self.profileKeys[address] = key;
}

- (void)setProfileGivenName:(nullable NSString *)givenName
                 familyName:(nullable NSString *)familyName
                 forAddress:(SignalServiceAddress *)address
        wasLocallyInitiated:(BOOL)wasLocallyInitiated
                transaction:(SDSAnyWriteTransaction *)transaction
{
    // Do nothing.
}

- (nullable NSData *)profileKeyDataForAddress:(SignalServiceAddress *)address
                                  transaction:(SDSAnyReadTransaction *)transaction
{
    return self.profileKeys[address].keyData;
}

- (BOOL)isUserInProfileWhitelist:(SignalServiceAddress *)address transaction:(SDSAnyReadTransaction *)transaction
{
    return [self.recipientWhitelist containsObject:address];
}

- (BOOL)isThreadInProfileWhitelist:(TSThread *)thread transaction:(SDSAnyReadTransaction *)transaction
{
    return [self.threadWhitelist containsObject:thread.uniqueId];
}

- (void)addUserToProfileWhitelist:(SignalServiceAddress *)address
{
    [self.recipientWhitelist addObject:address];
}

- (void)addUserToProfileWhitelist:(nonnull SignalServiceAddress *)address
              wasLocallyInitiated:(BOOL)wasLocallyInitiated
                      transaction:(nonnull SDSAnyWriteTransaction *)transaction
{
    [self.recipientWhitelist addObject:address];
}

- (void)removeUserFromProfileWhitelist:(SignalServiceAddress *)address
{
    [self.recipientWhitelist removeObject:address];
}

- (void)removeUserFromProfileWhitelist:(nonnull SignalServiceAddress *)address
                   wasLocallyInitiated:(BOOL)wasLocallyInitiated
                           transaction:(nonnull SDSAnyWriteTransaction *)transaction
{
    [self.recipientWhitelist removeObject:address];
}

- (BOOL)isGroupIdInProfileWhitelist:(NSData *)groupId transaction:(SDSAnyReadTransaction *)transaction
{
    return [self.threadWhitelist containsObject:groupId.hexadecimalString];
}

- (void)addGroupIdToProfileWhitelist:(NSData *)groupId
{
    [self.threadWhitelist addObject:groupId.hexadecimalString];
}

- (void)addGroupIdToProfileWhitelist:(nonnull NSData *)groupId
                 wasLocallyInitiated:(BOOL)wasLocallyInitiated
                         transaction:(nonnull SDSAnyWriteTransaction *)transaction
{
    [self.threadWhitelist addObject:groupId.hexadecimalString];
}

- (void)removeGroupIdFromProfileWhitelist:(NSData *)groupId
{
    [self.threadWhitelist removeObject:groupId.hexadecimalString];
}

- (void)removeGroupIdFromProfileWhitelist:(nonnull NSData *)groupId
                      wasLocallyInitiated:(BOOL)wasLocallyInitiated
                              transaction:(nonnull SDSAnyWriteTransaction *)transaction
{
    [self.threadWhitelist removeObject:groupId.hexadecimalString];
}

- (void)addThreadToProfileWhitelist:(TSThread *)thread
{
    if (thread.isGroupThread) {
        TSGroupThread *groupThread = (TSGroupThread *)thread;
        [self addGroupIdToProfileWhitelist:groupThread.groupModel.groupId];
    } else {
        TSContactThread *contactThread = (TSContactThread *)thread;
        [self addUserToProfileWhitelist:contactThread.contactAddress];
    }
}

- (void)addThreadToProfileWhitelist:(TSThread *)thread transaction:(SDSAnyWriteTransaction *)transaction
{
    if (thread.isGroupThread) {
        TSGroupThread *groupThread = (TSGroupThread *)thread;
        [self addGroupIdToProfileWhitelist:groupThread.groupModel.groupId];
    } else {
        TSContactThread *contactThread = (TSContactThread *)thread;
        [self addUserToProfileWhitelist:contactThread.contactAddress];
    }
}

- (void)fetchAndUpdateLocalUsersProfile
{
    // Do nothing.
}

- (void)updateProfileForAddress:(nonnull SignalServiceAddress *)address
{
    // Do nothing.
}

- (void)warmCaches
{
    // Do nothing.
}

- (BOOL)hasLocalProfile
{
    return (self.localGivenName.length > 0 || self.localProfileAvatarImage != nil);
}

- (BOOL)hasProfileName
{
    return self.localGivenName.length > 0;
}

- (nullable UIImage *)localProfileAvatarImage
{
    NSData *_Nullable data = self.localProfileAvatarData;
    if (data == nil) {
        return nil;
    }

    return [UIImage imageWithData:data];
}

- (BOOL)localProfileExistsWithTransaction:(nonnull SDSAnyReadTransaction *)transaction
{
    return self.hasLocalProfile;
}

@end

#endif

NS_ASSUME_NONNULL_END
