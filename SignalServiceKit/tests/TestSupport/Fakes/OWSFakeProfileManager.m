//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSFakeProfileManager.h"
#import "TSThread.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSFakeProfileManager ()

@property (nonatomic, readonly) NSMutableDictionary<NSString *, NSData *> *profileKeys;
@property (nonatomic, readonly) NSMutableSet<NSString *> *recipientWhitelist;
@property (nonatomic, readonly) NSMutableSet<NSString *> *threadWhitelist;

@end

@implementation OWSFakeProfileManager

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


- (NSData *)localProfileKey
{
    return [@"fake-local-profile-key-for-testing" dataUsingEncoding:NSUTF8StringEncoding];
}

- (void)setProfileKey:(NSData *)profileKey forRecipientId:(NSString *)recipientId
{
    self.profileKeys[recipientId] = profileKey;
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

NS_ASSUME_NONNULL_END
