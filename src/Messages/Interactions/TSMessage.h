//  Created by Frederic Jacobs on 12/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.

#import "TSInteraction.h"

/**
 *  Abstract message class.
 */

typedef NS_ENUM(NSInteger, TSGroupMetaMessage) {
    TSGroupMessageNone,
    TSGroupMessageNew,
    TSGroupMessageUpdate,
    TSGroupMessageDeliver,
    TSGroupMessageQuit
};
@interface TSMessage : TSInteraction

@property (nonatomic, readonly) NSMutableArray<NSString *> *attachmentIds;
@property (nonatomic) NSString *body;
@property (nonatomic) TSGroupMetaMessage groupMetaMessage;

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         inThread:(TSThread *)thread
                      messageBody:(NSString *)body
                    attachmentIds:(NSArray<NSString *> *)attachmentIds;

- (BOOL)hasAttachments;

@end
