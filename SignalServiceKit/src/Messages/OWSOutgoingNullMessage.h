//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

#import <SignalServiceKit/TSOutgoingMessage.h>

NS_ASSUME_NONNULL_BEGIN

@class OWSVerificationStateSyncMessage;
@class TSContactThread;

@interface OWSOutgoingNullMessage : TSOutgoingMessage

- (instancetype)initOutgoingMessageWithBuilder:(TSOutgoingMessageBuilder *)outgoingMessageBuilder
                                   transaction:(SDSAnyReadTransaction *)transaction NS_UNAVAILABLE;

- (instancetype)initWithContactThread:(TSContactThread *)contactThread
                          transaction:(SDSAnyReadTransaction *)transaction NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithContactThread:(TSContactThread *)contactThread
         verificationStateSyncMessage:(OWSVerificationStateSyncMessage *)verificationStateSyncMessage
                          transaction:(SDSAnyReadTransaction *)transaction NS_DESIGNATED_INITIALIZER;
;

@end

NS_ASSUME_NONNULL_END
