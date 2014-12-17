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

@interface TSMessage : TSInteraction

@property (nonatomic, readonly) NSMutableArray  *attachements;
@property (nonatomic, readonly) NSString        *body;

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         inThread:(TSThread*)thread
                      messageBody:(NSString*)body
                     attachements:(NSArray*)attachements;

- (void)addAttachements:(NSArray*)attachements;
- (void)addAttachement:(NSString*)attachement;
- (BOOL)hasAttachements;

@end
