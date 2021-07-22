//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "ProtoUtils.h"
#import "ProfileManagerProtocol.h"
#import "SSKEnvironment.h"
#import "TSThread.h"
#import <SignalCoreKit/Cryptography.h>
#import <SessionMessagingKit/SessionMessagingKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@implementation ProtoUtils

#pragma mark - Dependencies

+ (id<ProfileManagerProtocol>)profileManager {
    return SSKEnvironment.shared.profileManager;
}

+ (OWSAES256Key *)localProfileKey
{
    return [[LKStorage.shared getUser] profileEncryptionKey];
}

#pragma mark -

+ (BOOL)shouldMessageHaveLocalProfileKey:(TSThread *)thread recipientId:(NSString *_Nullable)recipientId
{
    return YES;
}

+ (void)addLocalProfileKeyIfNecessary:(TSThread *)thread
                          recipientId:(NSString *_Nullable)recipientId
                   dataMessageBuilder:(SNProtoDataMessageBuilder *)dataMessageBuilder
{
    if ([self shouldMessageHaveLocalProfileKey:thread recipientId:recipientId]) {
        [dataMessageBuilder setProfileKey:self.localProfileKey.keyData];
    }
}

+ (void)addLocalProfileKeyToDataMessageBuilder:(SNProtoDataMessageBuilder *)dataMessageBuilder
{
    [dataMessageBuilder setProfileKey:self.localProfileKey.keyData];
}

@end

NS_ASSUME_NONNULL_END
