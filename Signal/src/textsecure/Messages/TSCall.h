//
//  TSCall.h
//  TextSecureKit
//
//  Created by Frederic Jacobs on 12/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "TSInteraction.h"
#import "Contact.h"

#import "RecentCall.h"

@interface TSCall : TSInteraction

@property (nonatomic, readonly)RPRecentCallType callType;

- (instancetype)initWithTimestamp:(uint64_t)timeStamp
                   withCallNumber:(NSString*)contactNumber
                         callType:(RPRecentCallType)callType
                         inThread:(TSContactThread*)thread;

@end
