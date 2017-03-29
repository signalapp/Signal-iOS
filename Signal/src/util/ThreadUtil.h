//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

@class TSThread;
@class OWSMessageSender;
@class SignalAttachment;

NS_ASSUME_NONNULL_BEGIN

@interface ThreadUtil : NSObject

+ (void)sendMessageWithText:(NSString *)text
                   inThread:(TSThread *)thread
              messageSender:(OWSMessageSender *)messageSender;

+ (void)sendMessageWithAttachment:(SignalAttachment *)attachment
                         inThread:(TSThread *)thread
                    messageSender:(OWSMessageSender *)messageSender;

@end

NS_ASSUME_NONNULL_END
