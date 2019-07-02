//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "ProtoUtils.h"
#import "ProfileManagerProtocol.h"
#import "SSKEnvironment.h"
#import "TSThread.h"
#import <SignalCoreKit/Cryptography.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@implementation ProtoUtils

#pragma mark - Dependencies

+ (id<ProfileManagerProtocol>)profileManager {
    return SSKEnvironment.shared.profileManager;
}

+ (OWSAES256Key *)localProfileKey
{
    return self.profileManager.localProfileKey;
}

#pragma mark -

+ (BOOL)shouldMessageHaveLocalProfileKey:(TSThread *)thread recipientId:(NSString *_Nullable)recipientId
{
    OWSAssertDebug(thread);

    // For 1:1 threads, we want to include the profile key IFF the
    // contact is in the whitelist.
    //
    // For Group threads, we want to include the profile key IFF the
    // recipient OR the group is in the whitelist.
    if (recipientId.length > 0 &&
        [self.profileManager isUserInProfileWhitelist:recipientId.transitional_signalServiceAddress]) {
        return YES;
    } else if ([self.profileManager isThreadInProfileWhitelist:thread]) {
        return YES;
    }

    return NO;
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
            // FIXME PERF avoid this dispatch. It's going to happen for *each* recipient in a group message.
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.profileManager addUserToProfileWhitelist:recipientId.transitional_signalServiceAddress];
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
        // FIXME PERF avoid this dispatch. It's going to happen for *each* recipient in a group message.
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.profileManager addUserToProfileWhitelist:recipientId.transitional_signalServiceAddress];
        });
    }
}

@end

NS_ASSUME_NONNULL_END
