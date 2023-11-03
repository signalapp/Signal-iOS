//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
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

@protocol SyncManagerProtocol;
@protocol SyncManagerProtocolObjc;

@interface OWSSyncManager : NSObject <SyncManagerProtocolObjc>

+ (SDSKeyValueStore *)keyValueStore;

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initDefault NS_DESIGNATED_INITIALIZER;

@property (nonatomic) BOOL isRequestInFlight;

@end

NS_ASSUME_NONNULL_END
