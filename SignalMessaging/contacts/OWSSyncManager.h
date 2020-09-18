//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const OWSSyncManagerConfigurationSyncDidCompleteNotification;
extern NSString *const OWSSyncManagerKeysSyncDidCompleteNotification;

@class AnyPromise;
@class MessageSender;
@class OWSContactsManager;
@class OWSIdentityManager;
@class OWSProfileManager;
@class SDSKeyValueStore;

@interface OWSSyncManager : NSObject <SyncManagerProtocolObjc>

+ (SDSKeyValueStore *)keyValueStore;

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initDefault NS_DESIGNATED_INITIALIZER;

+ (id<SyncManagerProtocol>)shared;

@end

NS_ASSUME_NONNULL_END
