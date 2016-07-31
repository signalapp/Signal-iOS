//
//  TSIncomingMessage.h
//  TextSecureKit
//
//  Created by Frederic Jacobs on 15/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSMessage.h"

@class TSContactThread;
@class TSGroupThread;

@interface TSIncomingMessage : TSMessage

/**
 *  Initiates an incoming message
 *
 *  @param timestamp
 *    Timestamp of the message in milliseconds since epoch
 *  @param thread
 *    Thread to which the message belongs
 *  @param body
 *    Body of the message
 *  @param attachmentIds
 *    The uniqueIds for the message's attachments
 *
 *  @return initiated incoming message
 */

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         inThread:(TSContactThread *)thread
                      messageBody:(NSString *)body
                    attachmentIds:(NSArray<NSString *> *)attachmentIds;

/**
 *  Initiates an incoming group message
 *
 *  @param timestamp
 *    Timestamp of the message in milliseconds since epoch
 *  @param thread
 *    Thread to which the message belongs
 *  @param authorId
 *    Author identifier of the user in the group that sent the message
 *  @param body
 *    Body of the message
 *  @param attachmentIds
 *    The uniqueIds for the message's attachments
 *
 *  @return initiated incoming group message
 */

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         inThread:(TSGroupThread *)thread
                         authorId:(NSString *)authorId
                      messageBody:(NSString *)body
                    attachmentIds:(NSArray<NSString *> *)attachmentIds;

@property (nonatomic, readonly) NSString *authorId;
@property (nonatomic, getter=wasRead) BOOL read;
@property (nonatomic, readonly) NSDate *receivedAt;

@end
