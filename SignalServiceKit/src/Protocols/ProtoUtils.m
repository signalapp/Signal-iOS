//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "ProtoUtils.h"
#import "ProfileManagerProtocol.h"
#import "SSKEnvironment.h"
#import "TSThread.h"
#import <SignalCoreKit/Cryptography.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@implementation ProtoUtils

+ (OWSAES256Key *)localProfileKey
{
    return self.profileManager.localProfileKey;
}

#pragma mark -

+ (BOOL)shouldMessageHaveLocalProfileKey:(TSThread *)thread
                             transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(thread);
    OWSAssertDebug(transaction);

    // Group threads will return YES if the group is in the whitelist
    // Contact threads will return YES if the contact is in the whitelist.
    return [self.profileManager isThreadInProfileWhitelist:thread transaction:transaction];
}

+ (void)addLocalProfileKeyIfNecessary:(TSThread *)thread
                   dataMessageBuilder:(SSKProtoDataMessageBuilder *)dataMessageBuilder
                          transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(thread);
    OWSAssertDebug(dataMessageBuilder);
    OWSAssertDebug(transaction);

    if ([self shouldMessageHaveLocalProfileKey:thread transaction:transaction]) {
        [dataMessageBuilder setProfileKey:self.localProfileKey.keyData];
    }
}

+ (void)addLocalProfileKeyToDataMessageBuilder:(SSKProtoDataMessageBuilder *)dataMessageBuilder
{
    OWSAssertDebug(dataMessageBuilder);

    [dataMessageBuilder setProfileKey:self.localProfileKey.keyData];
}

+ (void)addLocalProfileKeyIfNecessary:(TSThread *)thread
                   callMessageBuilder:(SSKProtoCallMessageBuilder *)callMessageBuilder
                          transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(thread);
    OWSAssertDebug(callMessageBuilder);
    OWSAssertDebug(transaction);

    if ([self shouldMessageHaveLocalProfileKey:thread transaction:transaction]) {
        [callMessageBuilder setProfileKey:self.localProfileKey.keyData];
    }
}

+ (nullable NSString *)parseProtoE164:(nullable NSString *)value name:(NSString *)name
{
    if (value == nil) {
        OWSFailDebug(@"%@ was unexpectedly nil.", name);
        return nil;
    }
    if (value.length == 0) {
        OWSFailDebug(@"%@ was unexpectedly empty.", name);
        return nil;
    }
    if (!value.isStructurallyValidE164) {
        if (SSKDebugFlags.internalLogging) {
            OWSFailDebug(@"%@ was unexpectedly invalid: %@.", name, value);
        }
        OWSFailDebug(@"%@ was unexpectedly invalid.", name);
        return nil;
    }
    return value;
}

@end

NS_ASSUME_NONNULL_END
