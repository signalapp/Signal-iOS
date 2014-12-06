//
//  TSGroupMessageManager.m
//  TextSecureKit
//
//  Created by Frederic Jacobs on 15/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <CocoaLumberjack/DDLog.h>

#import "TSGroup.h"
#import "TSGroupMessageManager.h"

#define ddLogLevel LOG_LEVEL_VERBOSE


@implementation TSGroupMessageManager

+ (void)processGroupMessage:(IncomingPushMessageSignal*)pushMessage content:(PushMessageContent*)content{
    if (!content.group.id) {
        DDLogInfo(@"Received group message with no id! Ignoring...");
        return;
    }
    
    PushMessageContentGroupContext *group = content.group;
    NSData *id = group.id;
    int    type = group.type;
    TSGroup *record = [TSGroup groupWithId:id];
    
    if (record != nil && type == PushMessageContentGroupContextTypeUpdate) {
        //TODO: [self handleGroupUpdate:pushMessage group:group record:record];
    } else if (record == nil && type == PushMessageContentGroupContextTypeUpdate) {
        [self handleGroupCreate:pushMessage group:group record:record];
    } else if (record != nil && type == PushMessageContentGroupContextTypeQuit) {
        [self handleGroupLeave:pushMessage group:group record:record];
    } else if (type == PushMessageContentGroupContextTypeUnknown) {
        DDLogInfo(@"Received unknown type, ignoring...");
    }
}

+ (void)handleGroupCreate:(IncomingPushMessageSignal*)message group:(PushMessageContentGroupContext*)group record:(TSGroup*)record{
    //TODO
}

+ (void)handleGroupLeave:(IncomingPushMessageSignal*)pushMessage group:(PushMessageContentGroupContext*)group record:(TSGroup*)record{
    //TODO
}


//+ (void)handleGroupUpdate:(IncomingPushMessageSignal*)pushMessage group:(PushMessageContentGroupContext*)group record:(TSGroup*)record{
//    NSData  *identifier = group.id;
//    NSArray *messageMembersIds = group.members;
//    
//    NSSet *recordMembers  = record.membersIdentifier;
//    NSSet *messageMembers = [NSSet setWithArray:messageMembersIds];
//    
//    NSMutableSet *addedMembers   = [messageMembers mutableCopy];
//    [addedMembers minusSet:recordMembers];
//
//    NSMutableSet missingMembers = [recordMembers mutableCopy];
//    [missingMembers minusSet:messageMembers];
//    
//    if (addedMembers.count > 0) {
//        Set<String> unionMembers = new HashSet<String>(recordMembers);
//        unionMembers.addAll(messageMembers);
//        database.updateMembers(id, new LinkedList<String>(unionMembers));
//        
//        group = group.toBuilder().clearMembers().addAllMembers(addedMembers).build();
//
//    } else {
//        group = group.toBuilder().clearMembers().build();
//    }
//    
//    if (missingMembers > 0) {
//        
//    }
//    
//    if (group.hasName || group.hasAvatar) {
//        record.avatar = group.avatar;
//        record.name   = group.name;
//        [record save];
//    }
//    
//    // TO-DO: Implement
//    
//}

@end
