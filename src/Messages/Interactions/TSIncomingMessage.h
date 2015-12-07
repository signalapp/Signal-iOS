//
//  TSIncomingMessage.h
//  TextSecureKit
//
//  Created by Frederic Jacobs on 15/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSMessage.h"

@interface TSIncomingMessage : TSMessage

/**
 *  Initiates an incoming message
 *
 *  @param timestamp    timestamp of the message in milliseconds since epoch
 *  @param thread       thread to which the message belongs
 *  @param body         body of the message
 *  @param attachments attachments of the message
 *
 *  @return initiated incoming message
 */

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         inThread:(TSContactThread *)thread
                      messageBody:(NSString *)body
                      attachments:(NSArray *)attachments;

/**
 *  Initiates an incoming group message
 *
 *  @param timestamp    timestamp of the message in milliseconds since epoch
 *  @param thread       thread to which the message belongs
 *  @param authorId     author identifier of the user in the group that sent the message
 *  @param body         body of the message
 *  @param attachments attachments of the message
 *
 *  @return initiated incoming group message
 */

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         inThread:(TSGroupThread *)thread
                         authorId:(NSString *)authorId
                      messageBody:(NSString *)body
                      attachments:(NSArray *)attachments;

@property (nonatomic, readonly) NSString *authorId;
@property (nonatomic, getter=wasRead) BOOL read;
@property (nonatomic, readonly) NSDate *receivedAt;

@end
