//
//  TSDatabaseView.m
//  TextSecureKit
//
//  Created by Frederic Jacobs on 17/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSDatabaseView.h"

#import <YapDatabase/YapDatabaseView.h>

#import "TSThread.h"
#import "TSIncomingMessage.h"
#import "TSInteraction.h"
#import "TSStorageManager.h"
#import "TSRecipient.h"

NSString *TSInboxGroup                       = @"TSInboxGroup";
NSString *TSArchiveGroup                     = @"TSArchiveGroup";

NSString *TSUnreadIncomingMessagesGroup      = @"TSUnreadIncomingMessagesGroup";

NSString *TSThreadDatabaseViewExtensionName  = @"TSThreadDatabaseViewExtensionName";
NSString *TSMessageDatabaseViewExtensionName = @"TSMessageDatabaseViewExtensionName";
NSString *TSUnreadDatabaseViewExtensionName  = @"TSUnreadDatabaseViewExtensionName";

@implementation TSDatabaseView

+ (BOOL)registerUnreadDatabaseView {
    
    YapDatabaseView *unreadView = [[TSStorageManager sharedManager].database registeredExtension:TSUnreadDatabaseViewExtensionName];
    if (unreadView) {
        return YES;
    }
    
    YapDatabaseViewGrouping *viewGrouping = [YapDatabaseViewGrouping withObjectBlock:^NSString *(NSString *collection, NSString *key, id object) {
        if ([object isKindOfClass:[TSIncomingMessage class]]){
            TSIncomingMessage *message = (TSIncomingMessage*)object;
            if (message.read == NO){
                return message.uniqueThreadId;
            }
        }
        return nil;
    }];
    
    YapDatabaseViewSorting *viewSorting = [self messagesSorting];
    
    YapDatabaseViewOptions *options = [[YapDatabaseViewOptions alloc] init];
    options.isPersistent            = YES;
    options.allowedCollections      = [[YapWhitelistBlacklist alloc] initWithWhitelist:[NSSet setWithObject:[TSInteraction collection]]];
    
    YapDatabaseView *view = [[YapDatabaseView alloc] initWithGrouping:viewGrouping
                                                              sorting:viewSorting
                                                           versionTag:@"1"
                                                              options:options];
    
    return [[TSStorageManager sharedManager].database registerExtension:view withName:TSUnreadDatabaseViewExtensionName];
}

+ (BOOL)registerThreadDatabaseView {
    YapDatabaseView *threadView = [[TSStorageManager sharedManager].database registeredExtension:TSThreadDatabaseViewExtensionName];
    if (threadView) {
        return YES;
    }
    
    YapDatabaseViewGrouping *viewGrouping = [YapDatabaseViewGrouping withObjectBlock:^NSString *(NSString *collection, NSString *key, id object) {
        if ([object isKindOfClass:[TSThread class]]){
            TSThread *thread = (TSThread*)object;
            
            if (thread.lastMessageDate) {
                if (thread.archivalDate) {
                    return ([self threadShouldBeInInbox:thread])?TSInboxGroup:TSArchiveGroup;
                }
                return TSInboxGroup;
            }
        }
        return nil;
    }];
    
    YapDatabaseViewSorting *viewSorting = [self threadSorting];
    
    YapDatabaseViewOptions *options = [[YapDatabaseViewOptions alloc] init];
    options.isPersistent = YES;
    options.allowedCollections = [[YapWhitelistBlacklist alloc] initWithWhitelist:[NSSet setWithObject:[TSThread collection]]];
    
    YapDatabaseView *databaseView = [[YapDatabaseView alloc] initWithGrouping:viewGrouping
                                                                      sorting:viewSorting
                                                                   versionTag:@"1"
                                                                      options:options];
    
    return [[TSStorageManager sharedManager].database registerExtension:databaseView withName:TSThreadDatabaseViewExtensionName];
}

+ (BOOL)registerBuddyConversationDatabaseView {
    if ([[TSStorageManager sharedManager].database registeredExtension:TSMessageDatabaseViewExtensionName]) {
        return YES;
    }
    
    YapDatabaseViewGrouping *viewGrouping = [YapDatabaseViewGrouping withObjectBlock:^NSString *(NSString *collection, NSString *key, id object) {
        if ([object isKindOfClass:[TSInteraction class]]){
            return ((TSInteraction *)object).uniqueThreadId;
        }
        return nil;
    }];
    
    YapDatabaseViewSorting *viewSorting = [self messagesSorting];
    
    YapDatabaseViewOptions *options = [[YapDatabaseViewOptions alloc] init];
    options.isPersistent = YES;
    options.allowedCollections = [[YapWhitelistBlacklist alloc] initWithWhitelist:[NSSet setWithObject:[TSInteraction collection]]];
    
    YapDatabaseView *view = [[YapDatabaseView alloc] initWithGrouping:viewGrouping
                                                              sorting:viewSorting
                                                           versionTag:@"1"
                                                              options:options];
    
    return [[TSStorageManager sharedManager].database registerExtension:view withName:TSMessageDatabaseViewExtensionName];
}


/**
 *  Determines whether a thread belongs to the archive or inbox
 *
 *  @param thread TSThread
 *
 *  @return Inbox if true, Archive if false
 */

+ (BOOL)threadShouldBeInInbox:(TSThread*)thread {
    NSDate *lastMessage  = thread.lastMessageDate;
    NSDate *archivalDate = thread.archivalDate;
    
    if (lastMessage&&archivalDate) {
        return ([lastMessage timeIntervalSinceDate:archivalDate]>0)?YES:NO;
    }
    
    return YES;
}

+ (YapDatabaseViewSorting*)threadSorting {
    return [YapDatabaseViewSorting withObjectBlock:^NSComparisonResult(NSString *group, NSString *collection1, NSString *key1, id object1, NSString *collection2, NSString *key2, id object2) {
        if ([group isEqualToString:TSArchiveGroup] || [group isEqualToString:TSInboxGroup]) {
            if ([object1 isKindOfClass:[TSThread class]] && [object2 isKindOfClass:[TSThread class]]){
                TSThread *thread1 = (TSThread*)object1;
                TSThread *thread2 = (TSThread*)object2;
                
                return [thread2.lastMessageDate compare:thread1.lastMessageDate];
            }
        }
        return NSOrderedSame;
    }];

}

+ (YapDatabaseViewSorting*)messagesSorting {
    return [YapDatabaseViewSorting withObjectBlock:^NSComparisonResult(NSString *group, NSString *collection1, NSString *key1, id object1, NSString *collection2, NSString *key2, id object2) {
        
        if ([object1 isKindOfClass:[TSInteraction class]] && [object2 isKindOfClass:[TSInteraction class]]) {
            TSInteraction *message1 = (TSInteraction*)object1;
            TSInteraction *message2 = (TSInteraction*)object2;
            
            return [message1.date compare:message2.date];
        }
        
        return NSOrderedSame;
    }];
}

@end
