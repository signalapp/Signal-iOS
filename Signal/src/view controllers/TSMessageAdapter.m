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

// for InfoMessages

@property NSInteger infoMessageType;

// for ErrorMessages

@property NSInteger errorMessageType;

// for outgoing Messages only

@property NSInteger outgoingMessageStatus;

// ---

@property (nonatomic, copy)   NSDate   *messageDate;
@property (nonatomic, retain) NSString *messageBody;

@property NSUInteger identifier;

@end


@implementation TSMessageAdapter

+ (instancetype)messageViewDataWithInteraction:(TSInteraction*)interaction inThread:(TSThread*)thread{
    
    TSMessageAdapter *adapter = [[TSMessageAdapter alloc] init];
    adapter.messageDate = interaction.date;
    adapter.identifier  = (NSUInteger)interaction.uniqueId;

    if ([thread isKindOfClass:[TSContactThread class]]) {
        adapter.thread = (TSContactThread*)thread;
        if ([interaction isKindOfClass:[TSIncomingMessage class]]) {
            NSString *contactId       = ((TSContactThread*)thread).contactIdentifier;
            adapter.senderId          = contactId;
            adapter.senderDisplayName = contactId;
            adapter.messageType       = TSIncomingMessageAdapter;
        } else {
            adapter.senderId   = ME_MESSAGE_IDENTIFIER;
            adapter.senderDisplayName = @"Me";
            adapter.messageType = TSOutgoingMessageAdapter;
        }
    } else if ([thread isKindOfClass:[TSGroupThread class]]){
        if ([interaction isKindOfClass:[TSIncomingMessage class]]) {
            TSIncomingMessage *message = (TSIncomingMessage*)interaction;
            adapter.senderId   = message.authorId;
            adapter.senderDisplayName = message.authorId;
        } else {
            adapter.senderId   = ME_MESSAGE_IDENTIFIER;
            adapter.senderDisplayName = @"Me";
        }
    }
    
    if ([interaction isKindOfClass:[TSIncomingMessage class]] || [interaction isKindOfClass:[TSOutgoingMessage class]]) {
        TSMessage *message = (TSMessage*)interaction;
        adapter.messageBody = message.body;
    } else if ([interaction isKindOfClass:[TSCall class]]){
        adapter.messageBody = @"Placeholder for TSCalls";
        adapter.messageType = TSCallAdapter;
    } else if ([interaction isKindOfClass:[TSInfoMessage class]]){
        TSInfoMessage * infoMessage = (TSInfoMessage*)interaction;
        adapter.infoMessageType = infoMessage.messageType;
        adapter.messageBody = infoMessage.description;
        adapter.messageType = TSInfoMessageAdapter;
    } else {
        TSErrorMessage * errorMessage = (TSErrorMessage*)interaction;
        adapter.infoMessageType = errorMessage.errorType;
        adapter.messageBody = errorMessage.description;
        adapter.messageType = TSErrorMessageAdapter;
    }
    
    if ([interaction isKindOfClass:[TSOutgoingMessage class]]) {
        adapter.outgoingMessageStatus = ((TSOutgoingMessage*)interaction).messageState;
    }
    
    if ([interaction isKindOfClass:[TSOutgoingMessage class]]) {
        adapter.outgoingMessageStatus = ((TSOutgoingMessage*)interaction).messageState;
    }
    
    return adapter;
}

- (NSString*)senderId{
    if (_senderId) {
        return _senderId;
    }
    else{
        return ME_MESSAGE_IDENTIFIER;
    }
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

- (NSUInteger)hash{
    return self.identifier;
}

- (NSInteger)messageState{
    return self.outgoingMessageStatus;
}

@end
