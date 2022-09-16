//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

#import "OWSFakeProfileManager.h"
#import "FunctionalUtil.h"
#import "NSString+SSK.h"
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
@synthesize badgeStore = _badgeStore;

- (instancetype)init
{
    self = [super init];
    if (!self) {
        return self;
    }

    _profileKeys = [NSMutableDictionary new];
    _recipientWhitelist = [NSMutableSet new];
    _threadWhitelist = [NSMutableSet new];
    _stubbedStoriesCapabilitiesMap = [NSMutableDictionary new];
    _badgeStore = [[BadgeStore alloc] init];

    return self;
}

- (OWSAES256Key *)localProfileKey
{
    if (_localProfileKey == nil) {
        _localProfileKey = [OWSAES256Key generateRandomKey];
    }
    return _localProfileKey;
}

- (nullable OWSUserProfile *)getUserProfileForAddress:(SignalServiceAddress *)addressParam
                                          transaction:(SDSAnyReadTransaction *)transaction
{
    return nil;
}

- (NSDictionary<SignalServiceAddress *, OWSUserProfile *> *)
    getUserProfilesForAddresses:(NSArray<SignalServiceAddress *> *)addresses
                    transaction:(SDSAnyReadTransaction *)transaction
{
    return @{};
}

- (void)setProfileKeyData:(NSData *)profileKey
               forAddress:(SignalServiceAddress *)address
        userProfileWriter:(UserProfileWriter)userProfileWriter
              transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAES256Key *_Nullable key = [OWSAES256Key keyWithData:profileKey];
    OWSAssert(key);
    self.profileKeys[address] = key;
}

- (void)fillInMissingProfileKeys:(NSDictionary<SignalServiceAddress *, NSData *> *)profileKeys
               userProfileWriter:(UserProfileWriter)userProfileWriter
{
    for (SignalServiceAddress *address in profileKeys) {
        if (self.profileKeys[address] != nil) {
            continue;
        }
        NSData *_Nullable profileKeyData = profileKeys[address];
        OWSAssertDebug(profileKeyData);
        OWSAES256Key *_Nullable key = [OWSAES256Key keyWithData:profileKeyData];
        self.profileKeys[address] = key;
    }
}

- (void)setProfileGivenName:(nullable NSString *)givenName
                 familyName:(nullable NSString *)familyName
                 forAddress:(SignalServiceAddress *)address
          userProfileWriter:(UserProfileWriter)userProfileWriter
                transaction:(SDSAnyWriteTransaction *)transaction
{
    // Do nothing.
}

- (void)setProfileGivenName:(nullable NSString *)firstName
                 familyName:(nullable NSString *)lastName
              avatarUrlPath:(nullable NSString *)avatarUrlPath
                 forAddress:(nonnull SignalServiceAddress *)address
          userProfileWriter:(UserProfileWriter)userProfileWriter
                transaction:(nonnull SDSAnyWriteTransaction *)transaction
{
    // Do nothing.
}

- (nullable NSString *)fullNameForAddress:(SignalServiceAddress *)address
                              transaction:(SDSAnyReadTransaction *)transaction
{
    return @"some fake profile name";
}

- (nullable NSPersonNameComponents *)nameComponentsForProfileWithAddress:(SignalServiceAddress *)address
                                                             transaction:(SDSAnyReadTransaction *)transaction
{
    NSPersonNameComponents *components = [NSPersonNameComponents new];
    components.givenName = @"fake given name";
    components.familyName = @"fake family name";
    return components;
}

- (nullable NSData *)profileKeyDataForAddress:(SignalServiceAddress *)address
                                  transaction:(SDSAnyReadTransaction *)transaction
{
    return self.profileKeys[address].keyData;
}

- (nullable OWSAES256Key *)profileKeyForAddress:(SignalServiceAddress *)address
                                    transaction:(SDSAnyReadTransaction *)transaction
{
    return self.profileKeys[address];
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
                userProfileWriter:(UserProfileWriter)userProfileWriter
                      transaction:(nonnull SDSAnyWriteTransaction *)transaction
{
    [self.recipientWhitelist addObject:address];
}

- (void)addUsersToProfileWhitelist:(NSArray<SignalServiceAddress *> *)addresses
{
    [self.recipientWhitelist addObjectsFromArray:addresses];
}

- (void)addUsersToProfileWhitelist:(NSArray<SignalServiceAddress *> *)addresses
                 userProfileWriter:(UserProfileWriter)userProfileWriter
                       transaction:(SDSAnyWriteTransaction *)transaction
{
    [self.recipientWhitelist addObjectsFromArray:addresses];
}

- (void)removeUserFromProfileWhitelist:(SignalServiceAddress *)address
{
    [self.recipientWhitelist removeObject:address];
}

- (void)removeUserFromProfileWhitelist:(nonnull SignalServiceAddress *)address
                     userProfileWriter:(UserProfileWriter)userProfileWriter
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
                   userProfileWriter:(UserProfileWriter)userProfileWriter
                         transaction:(nonnull SDSAnyWriteTransaction *)transaction
{
    [self.threadWhitelist addObject:groupId.hexadecimalString];
}

- (void)removeGroupIdFromProfileWhitelist:(NSData *)groupId
{
    [self.threadWhitelist removeObject:groupId.hexadecimalString];
}

- (void)removeGroupIdFromProfileWhitelist:(nonnull NSData *)groupId
                        userProfileWriter:(UserProfileWriter)userProfileWriter
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

- (void)fetchLocalUsersProfile
{
    // Do nothing.
}

- (AnyPromise *)fetchLocalUsersProfilePromise
{
    // Do nothing.
    return [AnyPromise promiseWithValue:@(1)];
}

- (void)fetchProfileForAddress:(nonnull SignalServiceAddress *)address
{
    // Do nothing.
}

- (AnyPromise *)fetchProfileForAddressPromise:(SignalServiceAddress *)address
{
    return [AnyPromise promiseWithValue:@(1)];
}

- (AnyPromise *)fetchProfileForAddressPromise:(SignalServiceAddress *)address
                                  mainAppOnly:(BOOL)mainAppOnly
                             ignoreThrottling:(BOOL)ignoreThrottling
{
    return [AnyPromise promiseWithValue:@(1)];
}

- (void)warmCaches
{
    // Do nothing.
}

- (BOOL)recipientAddressIsStoriesCapable:(nonnull SignalServiceAddress *)address
                             transaction:(nonnull SDSAnyReadTransaction *)transaction
{
    NSNumber *_Nullable capability = self.stubbedStoriesCapabilitiesMap[address];
    if (capability == nil) {
        OWSFailDebug(@"unknown address %@ must be added to stubbedStoriesCapabilitiesMap.", address);
        return NO;
    }
    return capability.boolValue;
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

- (void)updateProfileForAddress:(SignalServiceAddress *)address
                      givenName:(nullable NSString *)givenName
                     familyName:(nullable NSString *)familyName
                            bio:(nullable NSString *)bio
                       bioEmoji:(nullable NSString *)bioEmoji
                       username:(nullable NSString *)username
               isStoriesCapable:(BOOL)isStoriesCapable
                  avatarUrlPath:(nullable NSString *)avatarUrlPath
          optionalAvatarFileUrl:(nullable NSURL *)optionalAvatarFileUrl
                  profileBadges:(nullable NSArray<OWSUserProfileBadgeInfo *> *)profileBadges
           canReceiveGiftBadges:(BOOL)canReceiveGiftBadges
                  lastFetchDate:(NSDate *)lastFetchDate
              userProfileWriter:(UserProfileWriter)userProfileWriter
                    transaction:(SDSAnyWriteTransaction *)writeTx
{
    // Do nothing.
}

- (void)localProfileWasUpdated:(OWSUserProfile *)localUserProfile
{
    // Do nothing.
}

- (AnyPromise *)downloadAndDecryptProfileAvatarForProfileAddress:(SignalServiceAddress *)profileAddress
                                                   avatarUrlPath:(NSString *)avatarUrlPath
                                                      profileKey:(OWSAES256Key *)profileKey
{
    return [AnyPromise promiseWithValue:@(1)];
}

- (nullable ModelReadCacheSizeLease *)leaseCacheSize:(NSInteger)size {
    return nil;
}

- (BOOL)hasProfileAvatarData:(SignalServiceAddress *)address transaction:(SDSAnyReadTransaction *)transaction
{
    return NO;
}

- (nullable NSData *)profileAvatarDataForAddress:(SignalServiceAddress *)address
                                     transaction:(SDSAnyReadTransaction *)transaction
{
    return nil;
}

- (nullable NSString *)profileAvatarURLPathForAddress:(SignalServiceAddress *)address
                                          transaction:(SDSAnyReadTransaction *)transaction
{
    return nil;
}

- (void)didSendOrReceiveMessageFromAddress:(SignalServiceAddress *)address
                               transaction:(SDSAnyWriteTransaction *)transaction
{
    // Do nothing.
}

- (void)reuploadLocalProfile
{
    // Do nothing.
}

- (nullable NSURL *)writeAvatarDataToFile:(nonnull NSData *)avatarData {
    return nil;
}

- (nonnull NSArray<id<SSKMaybeString>> *)fullNamesForAddresses:(nonnull NSArray<SignalServiceAddress *> *)addresses
                                                   transaction:(nonnull SDSAnyReadTransaction *)transaction
{
    NSMutableArray<id<SSKMaybeString>> *result = [NSMutableArray array];
    for (NSUInteger i = 0; i < addresses.count; i++) {
        if (self.fakeDisplayNames == nil) {
            [result addObject:@"some fake profile name"];
        } else {
            NSString *fakeName = self.fakeDisplayNames[addresses[i]];
            [result addObject:fakeName ?: [NSNull null]];
        }
    }
    return result;
}


- (void)migrateWhitelistedGroupsWithTransaction:(SDSAnyWriteTransaction *)transaction
{
    // Do nothing.
}

- (nullable NSString *)usernameForAddress:(SignalServiceAddress *)address
                              transaction:(SDSAnyReadTransaction *)transaction
{
    return self.fakeUsernames[address];
}

- (nonnull NSArray<id<SSKMaybeString>> *)usernamesForAddresses:(nonnull NSArray<SignalServiceAddress *> *)addresses
                                                   transaction:(nonnull SDSAnyReadTransaction *)transaction
{
    return [addresses map:^(SignalServiceAddress *address) { return self.fakeUsernames[address] ?: [NSNull null]; }];
}

- (NSArray<SignalServiceAddress *> *)allWhitelistedRegisteredAddressesWithTransaction:
    (SDSAnyReadTransaction *)transaction
{
    return @[];
}

@end

#endif

NS_ASSUME_NONNULL_END
