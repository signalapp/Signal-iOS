//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OutgoingCallEventSyncMessage.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@implementation OutgoingCallEvent

- (instancetype)initWithCallId:(uint64_t)callId
                          type:(OWSSyncCallEventType)type
                     direction:(OWSSyncCallEventDirection)direction
                         event:(OWSSyncCallEventEvent)event
                     timestamp:(uint64_t)timestamp
                      peerUuid:(NSData *)peerUuid
{
    self = [super init];
    if (!self) {
        return nil;
    }

    _callId = callId;
    _type = type;
    _direction = direction;
    _event = event;
    _timestamp = timestamp;
    _peerUuid = peerUuid;

    return self;
}

@end

#pragma mark -

@interface OutgoingCallEventSyncMessage ()

@property (nonatomic, readonly) OutgoingCallEvent *event;

@end

#pragma mark -

@implementation OutgoingCallEventSyncMessage

- (instancetype)initWithThread:(TSThread *)thread
                         event:(OutgoingCallEvent *)event
                   transaction:(SDSAnyReadTransaction *)transaction
{
    self = [super initWithThread:thread transaction:transaction];
    if (!self) {
        return nil;
    }

    _event = event;

    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    return [super initWithCoder:coder];
}

- (nullable SSKProtoSyncMessageBuilder *)syncMessageBuilderWithTransaction:(SDSAnyReadTransaction *)transaction
{
    return [self syncMessageBuilderWithCallEvent:self.event transaction:transaction];
}

- (BOOL)isUrgent
{
    return NO;
}

@end

NS_ASSUME_NONNULL_END
