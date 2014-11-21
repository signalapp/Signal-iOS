//
//  TSThread.m
//  TextSecureKit
//
//  Created by Frederic Jacobs on 16/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSThread.h"

#import "Environment.h"
#import "ContactsManager.h"
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

- (uint64_t)lastMessageId{
    return 0;
}

- (NSDate*)lastMessageDate{
    return [NSDate date];
}

- (UIImage*)image{
    return nil;
}

@end
