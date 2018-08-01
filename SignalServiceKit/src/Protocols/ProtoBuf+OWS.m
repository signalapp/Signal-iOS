//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "ProtoBuf+OWS.h"
#import "Cryptography.h"
#import "ProfileManagerProtocol.h"
#import "TSThread.h"
#import "TextSecureKitEnv.h"

NS_ASSUME_NONNULL_BEGIN

//@implementation PBGeneratedMessageBuilder (OWS)
//
//- (BOOL)shouldMessageHaveLocalProfileKey:(TSThread *)thread recipientId:(NSString *_Nullable)recipientId
//{
//    OWSAssert(thread);
//
//    id<ProfileManagerProtocol> profileManager = [TextSecureKitEnv sharedEnv].profileManager;
//
//    // For 1:1 threads, we want to include the profile key IFF the
//    // contact is in the whitelist.
//    //
//    // For Group threads, we want to include the profile key IFF the
//    // recipient OR the group is in the whitelist.
//    if (recipientId.length > 0 && [profileManager isUserInProfileWhitelist:recipientId]) {
//        return YES;
//    } else if ([profileManager isThreadInProfileWhitelist:thread]) {
//        return YES;
//    }
//
//    return NO;
//}
//
//- (OWSAES256Key *)localProfileKey
//{
//    id<ProfileManagerProtocol> profileManager = [TextSecureKitEnv sharedEnv].profileManager;
//    return profileManager.localProfileKey;
//}
//
//@end

#pragma mark -

@implementation SSKProtoDataMessageBuilder (OWS)

- (void)addLocalProfileKeyIfNecessary:(TSThread *)thread recipientId:(NSString *_Nullable)recipientId
{
    OWSAssert(thread);

    if ([self shouldMessageHaveLocalProfileKey:thread recipientId:recipientId]) {
        [self setProfileKey:self.localProfileKey.keyData];

        if (recipientId.length > 0) {
            // Once we've shared our profile key with a user (perhaps due to being
            // a member of a whitelisted group), make sure they're whitelisted.
            id<ProfileManagerProtocol> profileManager = [TextSecureKitEnv sharedEnv].profileManager;
            // FIXME PERF avoid this dispatch. It's going to happen for *each* recipient in a group message.
            dispatch_async(dispatch_get_main_queue(), ^{
                [profileManager addUserToProfileWhitelist:recipientId];
            });
        }
    }
}

- (void)addLocalProfileKey
{
    [self setProfileKey:self.localProfileKey.keyData];
}

@end

#pragma mark -

@implementation SSKProtoCallMessageBuilder (OWS)

- (void)addLocalProfileKeyIfNecessary:(TSThread *)thread recipientId:(NSString *)recipientId
{
    OWSAssert(thread);
    OWSAssert(recipientId.length > 0);

    if ([self shouldMessageHaveLocalProfileKey:thread recipientId:recipientId]) {
        [self setProfileKey:self.localProfileKey.keyData];

        // Once we've shared our profile key with a user (perhaps due to being
        // a member of a whitelisted group), make sure they're whitelisted.
        id<ProfileManagerProtocol> profileManager = [TextSecureKitEnv sharedEnv].profileManager;
        // FIXME PERF avoid this dispatch. It's going to happen for *each* recipient in a group message.
        dispatch_async(dispatch_get_main_queue(), ^{
            [profileManager addUserToProfileWhitelist:recipientId];
        });
    }
}

@end

NS_ASSUME_NONNULL_END
