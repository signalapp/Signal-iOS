//
//  TSCall.h
//  TextSecureKit
//
//  Created by Frederic Jacobs on 12/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "TSInteraction.h"

@interface TSCall : TSInteraction

typedef NS_ENUM(NSInteger, TSCallType) {
    TSCallTypeSuccess,
    TSCallTypeMissed,
    TSCallTypeBusy,
    TSCallTypeFailed
};

@property (nonatomic, readonly) NSNumber     *duration;
@property (nonatomic, readonly) BOOL         wasCaller;
@property (nonatomic, readonly) TSCallType   callType;

- (instancetype)initWithTimestamp:(uint64_t)timeStamp inThread:(TSThread*)thread
                       wasCaller:(BOOL)caller callType:(TSCallType)callType
                        duration:(NSNumber*)duration;

@end
