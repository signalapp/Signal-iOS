//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSFakeProfileManager.h"
#import "Cryptography.h"
#import "TSThread.h"

NS_ASSUME_NONNULL_BEGIN

#ifdef DEBUG

@interface OWSFakeProfileManager ()

@property (nonatomic, readonly) NSMutableDictionary<NSString *, OWSAES256Key *> *profileKeys;
@property (nonatomic, readonly) NSMutableSet<NSString *> *recipientWhitelist;
@property (nonatomic, readonly) NSMutableSet<NSString *> *threadWhitelist;
@property (nonatomic, readonly) OWSAES256Key *localProfileKey;

@end

@implementation OWSFakeProfileManager

@synthesize localProfileKey = _localProfileKey;

- (instancetype)init
{
    self = [super init];
    if (!self) {
        return self;
    }

    _profileKeys = [NSMutableDictionary new];
    _recipientWhitelist = [NSMutableSet new];
    _threadWhitelist = [NSMutableSet new];

    return self;
}


- (OWSAES256Key *)localProfileKey
{
    if (_localProfileKey == nil) {
        _localProfileKey = [OWSAES256Key generateRandomKey];
    }
    return _localProfileKey;
}

- (void)setProfileKeyData:(NSData *)profileKey forRecipientId:(NSString *)recipientId
{
    OWSAES256Key *key = [OWSAES256Key keyWithData:profileKey];
    NSAssert(key, @"Unable to build key. Invalid key data?");
    self.profileKeys[recipientId] = key;
}

- (BOOL)isUserInProfileWhitelist:(NSString *)recipientId
{
    return [self.recipientWhitelist containsObject:recipientId];
}

- (BOOL)isThreadInProfileWhitelist:(TSThread *)thread
{
    return [self.threadWhitelist containsObject:thread.uniqueId];
}

- (void)addUserToProfileWhitelist:(NSString *)recipientId
{
    [self.recipientWhitelist addObject:recipientId];
}

@end

#endif

NS_ASSUME_NONNULL_END
