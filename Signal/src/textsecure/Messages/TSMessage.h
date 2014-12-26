//
//  TSMessage.h
//  TextSecureKit
//
//  Created by Frederic Jacobs on 12/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSInteraction.h"
#import <Foundation/Foundation.h>

/**
 *  Abstract message class. Is instantiated by either
 */

typedef NS_ENUM(NSInteger, TSGroupMetaMessage){
    TSGroupMessageNone,
    TSGroupMessageNew,
    TSGroupMessageUpdate,
    TSGroupMessageDeliver,
    TSGroupMessageQuit
};
@interface TSMessage : TSInteraction

@property (nonatomic, readonly) NSMutableArray  *attachments;
@property (nonatomic, readonly) NSString        *body;
@property (nonatomic) TSGroupMetaMessage groupMetaMessage;

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         inThread:(TSThread*)thread
                      messageBody:(NSString*)body
                     attachments:(NSArray*)attachments;

- (void)addattachments:(NSArray*)attachments;
- (void)addattachment:(NSString*)attachment;
- (BOOL)hasAttachments;

@end
