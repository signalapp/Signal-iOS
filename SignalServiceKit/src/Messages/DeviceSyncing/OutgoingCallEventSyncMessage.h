//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <SignalServiceKit/OWSOutgoingSyncMessage.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_CLOSED_ENUM(NSUInteger, OWSSyncCallEventType) {
    OWSSyncCallEventType_AudioCall,
    OWSSyncCallEventType_VideoCall
};

typedef NS_CLOSED_ENUM(NSUInteger, OWSSyncCallEventDirection) {
    OWSSyncCallEventDirection_Incoming,
    OWSSyncCallEventDirection_Outgoing
};

// Enum name brought to you by the Department of Redundancy Department.
typedef NS_CLOSED_ENUM(NSUInteger, OWSSyncCallEventEvent) {
    OWSSyncCallEventEvent_Accepted,
    OWSSyncCallEventEvent_NotAccepted
};

@interface OutgoingCallEvent : MTLModel

@property (nonatomic, readonly) uint64_t callId;
@property (nonatomic, readonly) OWSSyncCallEventType type;
@property (nonatomic, readonly) OWSSyncCallEventDirection direction;
@property (nonatomic, readonly) OWSSyncCallEventEvent event;
@property (nonatomic, readonly) uint64_t timestamp;
@property (nonatomic, readonly) NSData *peerUuid;

- (instancetype)initWithCallId:(uint64_t)callId
                          type:(OWSSyncCallEventType)type
                     direction:(OWSSyncCallEventDirection)direction
                         event:(OWSSyncCallEventEvent)event
                     timestamp:(uint64_t)timestamp
                      peerUuid:(NSData *)peerUuid;

@end

#pragma mark -

@interface OutgoingCallEventSyncMessage : OWSOutgoingSyncMessage

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithThread:(TSThread *)thread transaction:(SDSAnyReadTransaction *)transaction NS_UNAVAILABLE;
- (instancetype)initWithThread:(TSThread *)thread
                         event:(OutgoingCallEvent *)event
                   transaction:(SDSAnyReadTransaction *)transaction NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithTimestamp:(uint64_t)timestamp
                           thread:(TSThread *)thread
                      transaction:(SDSAnyReadTransaction *)transaction NS_UNAVAILABLE;

- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
