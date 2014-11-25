//
//  TSMessageAdapter.m
//  Signal
//
//  Created by Frederic Jacobs on 24/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSMessageAdapter.h"
#import "TSIncomingMessage.h"
#import "TSOutgoingMessage.h"
#import "TSCall.h"
#import "TSInfoMessage.h"
#import "TSErrorMessage.h"

@interface TSMessageAdapter ()

// ---

@property (nonatomic, retain) TSContactThread *thread;

// OR for groups

@property (nonatomic, retain) NSString *senderId;
@property (nonatomic, retain) NSString *senderDisplayName;

// ---

@property (nonatomic, copy)   NSDate   *messageDate;
@property (nonatomic, retain) NSString *messageBody;

@end


@implementation TSMessageAdapter

+ (instancetype)messageViewDataWithInteraction:(TSInteraction*)interaction inThread:(TSThread*)thread{
    
    TSMessageAdapter *adapter = [[TSMessageAdapter alloc] init];
    adapter.messageDate = interaction.date;
    
    if ([thread isKindOfClass:[TSContactThread class]]) {
        adapter.thread = (TSContactThread*)thread;
    } else if ([thread isKindOfClass:[TSGroupThread class]]){
        if ([interaction isKindOfClass:[TSIncomingMessage class]]) {
            TSIncomingMessage *message = (TSIncomingMessage*)interaction;
            adapter.senderId   = message.authorId;
            adapter.senderDisplayName = message.authorId;
        } else{
            adapter.senderId   = @"self";
            adapter.senderDisplayName = @"Me";
        }
    }
    
    if ([interaction isKindOfClass:[TSMessage class]]) {
        TSMessage *message = (TSMessage*)interaction;
        adapter.messageBody = message.body;
    } else if ([interaction isKindOfClass:[TSCall class]]){
        adapter.messageBody = @"Placeholder for TSCalls";
    } else if ([interaction isKindOfClass:[TSInfoMessage class]]){
        adapter.messageBody = @"Placeholder for InfoMessage";
    } else{
        adapter.messageBody = @"Placeholder for ErrorMessage";
    }
    
    return adapter;
}


- (NSString*)senderId{
    return self.thread.uniqueId;
}

- (NSString *)senderDisplayName{
    if (self.thread) {
        return _thread.name;
    }
    return self.senderDisplayName;
}

- (NSDate *)date{
    return self.messageDate;
}

- (BOOL)isMediaMessage{
    return NO;
}

- (NSString *)text{
    return self.messageBody;
}

@end
