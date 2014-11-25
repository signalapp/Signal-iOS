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
#import "TSInteraction.h"
#import "TSStorageManager.h"
#import "TSGroup.h"

@implementation TSThread

+ (NSString *)collection{
    return @"TSThread";
}

- (instancetype)initWithUniqueId:(NSString *)uniqueId{
    self = [super initWithUniqueId:uniqueId];
    
    if (self) {
        _blocked       = NO;
        _lastMessageId = 0;
    }
    
    return self;
}

- (BOOL)isGroupThread{
    NSAssert(false, @"An abstract method on TSThread was called.");
    return FALSE;
}

- (uint64_t)lastMessageId{
    return _lastMessageId;
}

- (NSDate*)lastMessageDate{
    __block NSDate *date;
    [[TSStorageManager sharedManager].dbConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        date = [TSInteraction fetchObjectWithUniqueID:[TSInteraction stringFromTimeStamp:_lastMessageId] transaction:transaction].date;
    }];
    
    if (date) {
        return date;
    } else{
        return [NSDate date];
    }
}

- (UIImage*)image{
    return nil;
}

- (NSString*)lastMessageLabel{
    __block TSInteraction *interaction;
    [[TSStorageManager sharedManager].dbConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        interaction = [TSInteraction fetchObjectWithUniqueID:[TSInteraction stringFromTimeStamp:_lastMessageId] transaction:transaction];
    }];
    return interaction.description;
}

- (int)unreadMessages{
    return 0;
}

- (NSString *)name{
    NSAssert(FALSE, @"Should be implemented in subclasses");
    return nil;
}

@end
