//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import <SignalCoreKit/Cryptography.h>
#import <SignalServiceKit/ProfileManagerProtocol.h>
#import <SignalServiceKit/ProtoUtils.h>
#import <SignalServiceKit/SSKEnvironment.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/TSThread.h>

NS_ASSUME_NONNULL_BEGIN

@implementation ProtoUtils

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
