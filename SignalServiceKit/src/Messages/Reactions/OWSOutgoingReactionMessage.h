//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "TSOutgoingMessage.h"

NS_ASSUME_NONNULL_BEGIN

@class OWSReaction;

@interface OWSOutgoingReactionMessage : TSOutgoingMessage

- (instancetype)initOutgoingMessageWithBuilder:(TSOutgoingMessageBuilder *)outgoingMessageBuilder NS_UNAVAILABLE;

- (instancetype)initWithThread:(TSThread *)thread
                       message:(TSMessage *)message
                         emoji:(NSString *)emoji
                    isRemoving:(BOOL)isRemoving
              expiresInSeconds:(uint32_t)expiresInSeconds;

@property (nonatomic, nullable) OWSReaction *createdReaction;
@property (nonatomic, nullable) OWSReaction *previousReaction;

@end

NS_ASSUME_NONNULL_END
