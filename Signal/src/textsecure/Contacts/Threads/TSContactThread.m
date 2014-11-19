//
//  TSContactThread.m
//  TextSecureKit
//
//  Created by Frederic Jacobs on 16/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSContactThread.h"

#import "TSStorageManager.h"

#define TSContactThreadPrefix @"c"

@implementation TSContactThread

- (instancetype)initWithContactId:(NSString*)contactId{
    
    NSString *uniqueIdentifier = [[self class] threadIdFromContactId:contactId];
    
    self = [super initWithUniqueId:uniqueIdentifier];
    
    return self;
}

+ (instancetype)threadWithContactId:(NSString*)contactId{
    
    TSContactThread *thread = [self fetchObjectWithUniqueID:[self threadIdFromContactId:contactId]];
    
    if (!thread) {
        thread = [[TSContactThread alloc] initWithContactId:contactId];
        [thread save];
    }
    
    return thread;
}

- (NSString *)contactIdentifier{
    return [[self class]contactIdFromThreadId:self.uniqueId];
}

- (BOOL)isGroupThread{
    return false;
}

+ (NSString*)threadIdFromContactId:(NSString*)contactId{
    return [TSContactThreadPrefix stringByAppendingString:contactId];
}

+ (NSString*)contactIdFromThreadId:(NSString*)threadId{
    return [threadId substringWithRange:NSMakeRange(1, threadId.length-1)];
}

@end
