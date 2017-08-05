//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "ProfileManagerProtocol.h"
#import "ProtoBuf+OWS.h"
#import "SignalRecipient.h"
#import "TSThread.h"
#import "TextSecureKitEnv.h"

NS_ASSUME_NONNULL_BEGIN

@implementation PBGeneratedMessageBuilder (OWS)

- (BOOL)shouldMessageHaveLocalProfileKey:(TSThread *)thread recipientId:(NSString *_Nullable)recipientId
{
    OWSAssert(thread);

    id<ProfileManagerProtocol> profileManager = [TextSecureKitEnv sharedEnv].profileManager;

    // For 1:1 threads, we want to include the profile key IFF the
    // contact is in the whitelist.
    //
    // For Group threads, we want to include the profile key IFF the
    // recipient OR the group is in the whitelist.
    if (recipientId.length > 0 && [profileManager isUserInProfileWhitelist:recipientId]) {
        return YES;
    } else if ([profileManager isThreadInProfileWhitelist:thread]) {
        return YES;
    }

    return NO;
}

- (NSData *)localProfileKey
{
    id<ProfileManagerProtocol> profileManager = [TextSecureKitEnv sharedEnv].profileManager;
    return profileManager.localProfileKey;
}

@end

#pragma mark -

@implementation OWSSignalServiceProtosDataMessageBuilder (OWS)

- (void)addLocalProfileKeyIfNecessary:(TSThread *)thread recipientId:(NSString *_Nullable)recipientId
{
    OWSAssert(thread);

    if ([self shouldMessageHaveLocalProfileKey:thread recipientId:recipientId]) {
        [self setProfileKey:self.localProfileKey];

        if (recipientId.length > 0) {
            // Once we've shared our profile key with a user (perhaps due to being
            // a member of a whitelisted group), make sure they're whitelisted.
            id<ProfileManagerProtocol> profileManager = [TextSecureKitEnv sharedEnv].profileManager;
            [profileManager addUserToProfileWhitelist:recipientId];
        }
    }
}

@end

#pragma mark -

@implementation OWSSignalServiceProtosCallMessageBuilder (OWS)

- (void)addLocalProfileKeyIfNecessary:(TSThread *)thread recipientId:(NSString *)recipientId
{
    OWSAssert(thread);
    OWSAssert(recipientId.length > 0);

    if ([self shouldMessageHaveLocalProfileKey:thread recipientId:recipientId]) {
        [self setProfileKey:self.localProfileKey];

        // Once we've shared our profile key with a user (perhaps due to being
        // a member of a whitelisted group), make sure they're whitelisted.
        id<ProfileManagerProtocol> profileManager = [TextSecureKitEnv sharedEnv].profileManager;
        [profileManager addUserToProfileWhitelist:recipientId];
    }
}

@end

#pragma mark -

@implementation OWSSignalServiceProtosSyncMessageBuilder (OWS)

- (void)addLocalProfileKey
{
    [self setProfileKey:self.localProfileKey];
}

@end

NS_ASSUME_NONNULL_END
