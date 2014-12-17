//
//  TSGroupThread.m
//  TextSecureKit
//
//  Created by Frederic Jacobs on 16/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSGroupThread.h"
#import "NSData+Base64.h"

@implementation TSGroupThread

#define TSGroupThreadPrefix @"g"

- (instancetype)initWithGroupId:(NSData*)groupId groupName:(NSString*)groupName{
    
    NSString *uniqueIdentifier = [[self class] threadIdFromGroupId:groupId];
    
    self = [super initWithUniqueId:uniqueIdentifier];
    _groupName = groupName;
    return self;
}

+ (instancetype)threadWithGroupId:(NSData *)groupId groupName:(NSString*)groupName transaction:(YapDatabaseReadWriteTransaction*)transaction{
    //TODOGROUP
    TSGroupThread *thread = [self fetchObjectWithUniqueID:[self threadIdFromGroupId:groupId] transaction:transaction];

    if (!thread) {
        thread = [[TSGroupThread alloc] initWithGroupId:groupId groupName:groupName];
        [thread saveWithTransaction:transaction];
    }
    
    return thread;
}

- (BOOL)isGroupThread{
    return true;
}

- (NSData *)groupId{
    return [[self class] groupIdFromThreadId:self.uniqueId];
}


- (NSString*)name{
    //TODOGROUP
    return self.groupName;
}


+ (NSString*)threadIdFromGroupId:(NSData*)groupId{
    return [TSGroupThreadPrefix stringByAppendingString:[groupId base64EncodedString]];
}

+ (NSData*)groupIdFromThreadId:(NSString*)threadId{
    return [NSData dataFromBase64String:[threadId substringWithRange:NSMakeRange(1, threadId.length-1)]];
}

@end
