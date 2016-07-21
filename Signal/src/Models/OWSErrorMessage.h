//  Created by Dylan Bourgeois on 29/11/14.
//  Copyright (c) 2014 Hexed Bits. All rights reserved.
//  Portions Copyright (c) 2016 Open Whisper Systems. All rights reserved.

#import "OWSDisplayedMessage.h"
#import "TSMessageAdapter.h"

typedef NS_ENUM(NSInteger, OWSErrorMessageType) {
    OWSErrorMessageNoSession,
    OWSErrorMessageWrongTrustedIdentityKey,
    OWSErrorMessageInvalidKeyException,
    OWSErrorMessageMissingKeyId,
    OWSErrorMessageInvalidMessage,
    OWSErrorMessageDuplicateMessage,
    OWSErrorMessageInvalidVersion
};

@interface OWSErrorMessage : OWSDisplayedMessage

@property (nonatomic) OWSErrorMessageType errorMessageType;
@property (nonatomic) TSMessageAdapterType messageType;

#pragma mark - Initialization

- (instancetype)initWithErrorType:(OWSErrorMessageType)messageType
                         senderId:(NSString *)senderId
                senderDisplayName:(NSString *)senderDisplayName
                             date:(NSDate *)date;

- (NSString *)text;

@end
