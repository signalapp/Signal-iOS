//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>

@class TSThread;
@class OWSMessageSender;
@class SignalAttachment;

@interface ThreadUtil : NSObject

+ (void)sendMessageWithText:(NSString *)text
                   inThread:(TSThread *)thread
              messageSender:(OWSMessageSender *)messageSender;

+ (void)sendMessageWithAttachment:(SignalAttachment *)attachment
                         inThread:(TSThread *)thread
                    messageSender:(OWSMessageSender *)messageSender;

@end
