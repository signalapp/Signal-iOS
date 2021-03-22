//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

extern NSString *const OWSSyncManagerConfigurationSyncDidCompleteNotification;
extern NSString *const OWSSyncManagerKeysSyncDidCompleteNotification;

@class AnyPromise;
@class MessageSender;
@class OWSContactsManager;
@class OWSIdentityManager;
@class OWSProfileManager;
@class SDSKeyValueStore;

@protocol SyncManagerProtocol;
@protocol SyncManagerProtocolObjc;

@interface OWSSyncManager : NSObject <SyncManagerProtocolObjc>

+ (SDSKeyValueStore *)keyValueStore;

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initDefault NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
