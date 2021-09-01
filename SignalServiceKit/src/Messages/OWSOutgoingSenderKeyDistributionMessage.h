//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import "TSOutgoingMessage.h"

@class TSContactThread;

NS_ASSUME_NONNULL_BEGIN

@interface OWSOutgoingSenderKeyDistributionMessage : TSOutgoingMessage

- (instancetype)initOutgoingMessageWithBuilder:(TSOutgoingMessageBuilder *)outgoingMessageBuilder NS_UNAVAILABLE;
- (instancetype)initWithThread:(TSContactThread *)destinationThread
    senderKeyDistributionMessageBytes:(NSData *)skdmBytes;

/// Returns YES if this message is being sent as a precondition to sending an online-only message.
/// Typing indicators are only delivered to online devices. Since they're ephemeral we just don't bother sending a
/// typing indicator to a recipient if we need the user to verify a safety number change. Outgoing SKDMs being sent on
/// behalf of an outgoing typing indicator should inherit this behavior.
@property (assign, atomic, readonly) BOOL isSentOnBehalfOfOnlineMessage;
- (void)configureAsSentOnBehalfOf:(TSOutgoingMessage *)message NS_SWIFT_NAME(configureAsSentOnBehalfOf(_:));

@end

NS_ASSUME_NONNULL_END
