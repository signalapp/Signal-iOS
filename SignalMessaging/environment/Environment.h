//
// Copyright 2014 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class AvatarBuilder;
@class LightweightCallManager;
@class OWSPreferences;
@class OWSSounds;
@class SignalMessagingJobQueues;

@protocol OWSProximityMonitoringManager;

/**
 *
 * Environment is a data and data accessor class.
 * It handles application-level component wiring in order to support mocks for testing.
 * It also handles network configuration for testing/deployment server configurations.
 *
 **/
// TODO: Rename to SMGEnvironment?
@interface Environment : NSObject

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithPreferences:(OWSPreferences *)preferences
         proximityMonitoringManager:(id<OWSProximityMonitoringManager>)proximityMonitoringManager
                      avatarBuilder:(AvatarBuilder *)avatarBuilder
                        smJobQueues:(SignalMessagingJobQueues *)smJobQueues;

@property (nonatomic, readonly) id<OWSProximityMonitoringManager> proximityMonitoringManagerRef;
@property (nonatomic, readonly) OWSPreferences *preferencesRef;
@property (nonatomic, readonly) OWSSounds *soundsRef;
@property (nonatomic, readonly) AvatarBuilder *avatarBuilderRef;
@property (nonatomic, readonly) SignalMessagingJobQueues *signalMessagingJobQueuesRef;

// This property is configured after Environment is created.
@property (atomic, nullable) LightweightCallManager *lightweightCallManagerRef;

@property (class, nonatomic) Environment *shared;

@end

NS_ASSUME_NONNULL_END
