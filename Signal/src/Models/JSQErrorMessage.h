//
//  JSQErrorMessage.h
//  JSQMessages
//
//  Created by Dylan Bourgeois on 29/11/14.
//  Copyright (c) 2014 Hexed Bits. All rights reserved.
//

#import "JSQDisplayedMessage.h"

typedef NS_ENUM(NSInteger, JSQErrorMessageType){
    JSQErrorMessageNoSession,
    JSQErrorMessageWrongTrustedIdentityKey,
    JSQErrorMessageInvalidKeyException,
    JSQErrorMessageMissingKeyId,
    JSQErrorMessageInvalidMessage,
    JSQErrorMessageDuplicateMessage,
    JSQErrorMessageInvalidVersion
};

@interface JSQErrorMessage : JSQDisplayedMessage

@property (nonatomic) JSQErrorMessageType errorMessageType;

@property (nonatomic) TSMessageAdapterType messageType;

#pragma mark - Initialization

- (instancetype)initWithErrorType:(JSQErrorMessageType)messageType
                         senderId:(NSString*)senderId
                senderDisplayName:(NSString*)senderDisplayName
                             date:(NSDate*)date;

- (NSString*)text;

@end
