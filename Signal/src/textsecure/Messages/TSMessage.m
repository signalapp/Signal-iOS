//
//  TSMessage.m
//  TextSecureKit
//
//  Created by Frederic Jacobs on 12/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSMessage.h"


@implementation TSMessage

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         inThread:(TSThread*)thread
                      messageBody:(NSString*)body
                     attachements:(NSArray*)attachements
{
    self = [super initWithTimestamp:timestamp inThread:thread];
    
    if (self) {
        _body         = body;
        _attachements = attachements;
    }
    return self;
}

- (BOOL)hasAttachements{
    return self.attachements?(self.attachements.count>0):false;
}


@end
