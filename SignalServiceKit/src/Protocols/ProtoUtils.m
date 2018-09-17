//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "ProtoUtils.h"
#import "Cryptography.h"
#import "ProfileManagerProtocol.h"
#import "SSKEnvironment.h"
#import "TSThread.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@implementation ProtoUtils

+ (BOOL)shouldMessageHaveLocalProfileKey:(TSThread *)thread recipientId:(NSString *_Nullable)recipientId
{
    OWSAssertDebug(thread);

    id<ProfileManagerProtocol> profileManager = SSKEnvironment.shared.profileManager;

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

+ (OWSAES256Key *)localProfileKey
{
    id<ProfileManagerProtocol> profileManager = SSKEnvironment.shared.profileManager;
    return profileManager.localProfileKey;
}

+ (void)addLocalProfileKeyIfNecessary:(TSThread *)thread
                          recipientId:(NSString *_Nullable)recipientId
                   dataMessageBuilder:(SSKProtoDataMessageBuilder *)dataMessageBuilder
{
    OWSAssertDebug(thread);
    OWSAssertDebug(dataMessageBuilder);

    if ([self shouldMessageHaveLocalProfileKey:thread recipientId:recipientId]) {
        [dataMessageBuilder setProfileKey:self.localProfileKey.keyData];

        if (recipientId.length > 0) {
            // Once we've shared our profile key with a user (perhaps due to being
            // a member of a whitelisted group), make sure they're whitelisted.
            id<ProfileManagerProtocol> profileManager = SSKEnvironment.shared.profileManager;
            // FIXME PERF avoid this dispatch. It's going to happen for *each* recipient in a group message.
            dispatch_async(dispatch_get_main_queue(), ^{
                [profileManager addUserToProfileWhitelist:recipientId];
            });
        }
    }
}

+ (void)addLocalProfileKeyToDataMessageBuilder:(SSKProtoDataMessageBuilder *)dataMessageBuilder
{
    OWSAssertDebug(dataMessageBuilder);

    [dataMessageBuilder setProfileKey:self.localProfileKey.keyData];
}

+ (void)addLocalProfileKeyIfNecessary:(TSThread *)thread
                          recipientId:(NSString *)recipientId
                   callMessageBuilder:(SSKProtoCallMessageBuilder *)callMessageBuilder
{
    OWSAssertDebug(thread);
    OWSAssertDebug(recipientId.length > 0);
    OWSAssertDebug(callMessageBuilder);

    if ([self shouldMessageHaveLocalProfileKey:thread recipientId:recipientId]) {
        [callMessageBuilder setProfileKey:self.localProfileKey.keyData];

        // Once we've shared our profile key with a user (perhaps due to being
        // a member of a whitelisted group), make sure they're whitelisted.
        id<ProfileManagerProtocol> profileManager = SSKEnvironment.shared.profileManager;
        // FIXME PERF avoid this dispatch. It's going to happen for *each* recipient in a group message.
        dispatch_async(dispatch_get_main_queue(), ^{
            [profileManager addUserToProfileWhitelist:recipientId];
        });
    }
}

@end

NS_ASSUME_NONNULL_END
