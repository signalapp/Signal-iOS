//
//  TSMessage.m
//  TextSecureKit
//
//  Created by Frederic Jacobs on 12/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSMessage.h"


@implementation TSMessage

- (void)addAttachements:(NSArray*)attachements {
    for (NSString *identifier in attachements) {
        [self addAttachement:identifier];
    }
}

- (void)addAttachement:(NSString*)attachement {
    if (!_attachements) {
        _attachements = [NSMutableArray array];
    }
    
    [self.attachements addObject:attachement];
}

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                         inThread:(TSThread*)thread
                      messageBody:(NSString*)body
                     attachements:(NSArray*)attachements
{
    self = [super initWithTimestamp:timestamp inThread:thread];
    
    if (self) {
        _body         = body;
        _attachements = [attachements mutableCopy];
    }
    return self;
}

- (BOOL)hasAttachements{
    return self.attachements?(self.attachements.count>0):false;
}

- (NSString *)description{
    if(self.attachements > 0){
        return @"Attachement";
    } else {
        return self.body;
    }
}

@end
