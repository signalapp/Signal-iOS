//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
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

+ (BOOL)shouldMessageHaveLocalProfileKey:(TSThread *)thread
                                 address:(SignalServiceAddress *_Nullable)address
                             transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(thread);
    OWSAssertDebug(transaction);

    // For 1:1 threads, we want to include the profile key IFF the
    // contact is in the whitelist.
    //
    // For Group threads, we want to include the profile key IFF the
    // recipient OR the group is in the whitelist.
    if (address.isValid && [self.profileManager isUserInProfileWhitelist:address transaction:transaction]) {
        return YES;
    } else if ([self.profileManager isThreadInProfileWhitelist:thread transaction:transaction]) {
        return YES;
    }

    return NO;
}

+ (void)addLocalProfileKeyIfNecessary:(TSThread *)thread
                              address:(SignalServiceAddress *_Nullable)address
                   dataMessageBuilder:(SSKProtoDataMessageBuilder *)dataMessageBuilder
                          transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(thread);
    OWSAssertDebug(dataMessageBuilder);
    OWSAssertDebug(transaction);

    if ([self shouldMessageHaveLocalProfileKey:thread address:address transaction:transaction]) {
        [dataMessageBuilder setProfileKey:self.localProfileKey.keyData];
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
                          transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(thread);
    OWSAssertDebug(address.isValid);
    OWSAssertDebug(callMessageBuilder);
    OWSAssertDebug(transaction);

    if ([self shouldMessageHaveLocalProfileKey:thread address:address transaction:transaction]) {
        [callMessageBuilder setProfileKey:self.localProfileKey.keyData];
    }
}

@end

NS_ASSUME_NONNULL_END
