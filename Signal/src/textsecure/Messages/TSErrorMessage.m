//
//  TSErrorMessage.m
//  TextSecureKit
//
//  Created by Frederic Jacobs on 12/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSErrorMessage.h"

@implementation TSErrorMessage

- (instancetype)initWithTimestamp:(uint64_t)timestamp inThread:(TSThread *)thread failedMessageType:(TSErrorMessageType)errorMessageType{
    self = [super initWithTimestamp:timestamp inThread:thread messageBody:@"Error Message" attachements:nil];
    
    if (self) {
        _errorType = errorMessageType;
    }
    
    return self;
}

@end
