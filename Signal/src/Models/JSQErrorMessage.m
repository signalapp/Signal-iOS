//
//  JSQErrorMessage.m
//  JSQMessages
//
//  Created by Dylan Bourgeois on 29/11/14.
//  Copyright (c) 2014 Hexed Bits. All rights reserved.
//

#import "JSQErrorMessage.h"

@implementation JSQErrorMessage

- (instancetype)initWithErrorType:(JSQErrorMessageType)messageType
                         senderId:(NSString *)senderId
                senderDisplayName:(NSString *)senderDisplayName
                             date:(NSDate *)date
{
    self = [super initWithSenderId:senderId senderDisplayName:senderDisplayName date:date];
    
    if (self) {
        _errorMessageType = messageType;
        _messageType = TSErrorMessageAdapter;
    }
    
    return self;
}

- (NSString*)text
{
    switch (self.errorMessageType) {
        case JSQErrorMessageNoSession:
            return [NSString stringWithFormat:@"No session error"];
            break;
        case JSQErrorMessageWrongTrustedIdentityKey:
            return [NSString stringWithFormat:@"Error : Wrong trusted identity key for %@.", self.senderDisplayName];
            break;
        case JSQErrorMessageInvalidKeyException:
            return [NSString stringWithFormat:@"Error : Invalid key exception for %@.", self.senderDisplayName];
            break;
        case JSQErrorMessageMissingKeyId:
            return [NSString stringWithFormat:@"Error: Missing key identifier for %@", self.senderDisplayName];
            break;
        case JSQErrorMessageInvalidMessage:
            return [NSString stringWithFormat:@"Error: Invalid message"];
            break;
        case JSQErrorMessageDuplicateMessage:
            return [NSString stringWithFormat:@"Error: Duplicate message"];
            break;
        case JSQErrorMessageInvalidVersion:
            return [NSString stringWithFormat:@"Error: Invalid version for contact %@.", self.senderDisplayName];
            break;
            
        default:
            return nil;
            break;
    }
}

- (NSUInteger)hash
{
    return self.senderId.hash ^ self.date.hash;
}

- (NSString*)description
{
    return [NSString stringWithFormat:@"<%@: senderId=%@, senderDisplayName=%@, date=%@, type=%ld>",
            [self class], self.senderId, self.senderDisplayName, self.date, self.errorMessageType];
}

-(TSMessageAdapterType)messageType
{
    return TSErrorMessageAdapter;
}

@end
