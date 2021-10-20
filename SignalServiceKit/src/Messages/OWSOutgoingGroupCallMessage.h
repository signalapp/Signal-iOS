//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import <SignalServiceKit/TSOutgoingMessage.h>

@class TSGroupThread;

NS_ASSUME_NONNULL_BEGIN

@interface OWSOutgoingGroupCallMessage : TSOutgoingMessage

- (instancetype)initOutgoingMessageWithBuilder:(TSOutgoingMessageBuilder *)outgoingMessageBuilder NS_UNAVAILABLE;
- (instancetype)initWithThread:(TSGroupThread *)thread eraId:(nullable NSString *)eraId;

@end

NS_ASSUME_NONNULL_END
