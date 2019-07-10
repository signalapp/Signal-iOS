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

+ (BOOL)shouldMessageHaveLocalProfileKey:(TSThread *)thread address:(SignalServiceAddress *_Nullable)address
{
    OWSAssertDebug(thread);

    // For 1:1 threads, we want to include the profile key IFF the
    // contact is in the whitelist.
    //
    // For Group threads, we want to include the profile key IFF the
    // recipient OR the group is in the whitelist.
    if (address.isValid &&
        [self.profileManager isUserInProfileWhitelist:address]) {
        return YES;
    } else if ([self.profileManager isThreadInProfileWhitelist:thread]) {
        return YES;
    }

    return NO;
}

+ (void)addLocalProfileKeyIfNecessary:(TSThread *)thread
                          address:(SignalServiceAddress *_Nullable)address
                   dataMessageBuilder:(SSKProtoDataMessageBuilder *)dataMessageBuilder
{
    OWSAssertDebug(thread);
    OWSAssertDebug(dataMessageBuilder);

    if ([self shouldMessageHaveLocalProfileKey:thread address:address]) {
        [dataMessageBuilder setProfileKey:self.localProfileKey.keyData];

        if (address.isValid) {
            // Once we've shared our profile key with a user (perhaps due to being
            // a member of a whitelisted group), make sure they're whitelisted.
            // FIXME PERF avoid this dispatch. It's going to happen for *each* recipient in a group message.
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.profileManager addUserToProfileWhitelist:address];
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
                          address:(SignalServiceAddress *)address
                   callMessageBuilder:(SSKProtoCallMessageBuilder *)callMessageBuilder
{
    OWSAssertDebug(thread);
    OWSAssertDebug(address.isValid);
    OWSAssertDebug(callMessageBuilder);

    if ([self shouldMessageHaveLocalProfileKey:thread address:address]) {
        [callMessageBuilder setProfileKey:self.localProfileKey.keyData];

        // Once we've shared our profile key with a user (perhaps due to being
        // a member of a whitelisted group), make sure they're whitelisted.
        // FIXME PERF avoid this dispatch. It's going to happen for *each* recipient in a group message.
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.profileManager addUserToProfileWhitelist:address];
        });
    }
}

@end

NS_ASSUME_NONNULL_END
