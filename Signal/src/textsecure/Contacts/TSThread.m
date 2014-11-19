//
//  TSThread.m
//  TextSecureKit
//
//  Created by Frederic Jacobs on 16/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSThread.h"

#import "TSContact.h"
#import "TSGroup.h"

@implementation TSThread

+ (NSString *)collection{
    return @"TSThread";
}

- (instancetype)initWithUniqueId:(NSString *)uniqueId{
    self = [super initWithUniqueId:uniqueId];
    
    if (self) {
        _blocked = NO;
    }
    
    return self;
}

- (BOOL)isGroupThread{
    NSAssert(false, @"An abstract method on TSThread was called.");
    return FALSE;
}

@end
