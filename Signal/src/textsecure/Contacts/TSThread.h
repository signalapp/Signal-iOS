//
//  TSThread.h
//  TextSecureKit
//
//  Created by Frederic Jacobs on 16/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <YapDatabase/YapDatabaseRelationshipNode.h>

#import "TSYapDatabaseObject.h"

/**
 *  TSThread is the superclass of TSContactThread and TSGroupThread
 */

@interface TSThread : TSYapDatabaseObject

/**
 *  Returns whether the object is a group thread or not
 *
 *  @return Is a group
 */

- (BOOL)isGroupThread;

@property (getter=isBlocked) BOOL   blocked;
@property (nonatomic, copy)  NSDate *lastMessageDate;

@end
