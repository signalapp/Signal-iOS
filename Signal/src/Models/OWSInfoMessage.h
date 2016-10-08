//  Created by Dylan Bourgeois on 29/11/14.
//  Copyright (c) 2014 Hexed Bits. All rights reserved.
//  Portions Copyright (c) 2016 Open Whisper Systems. All rights reserved.

#import "OWSDisplayedMessage.h"
#import "TSInfoMessage.h"
#import "TSMessageAdapter.h"

@interface OWSInfoMessage : OWSDisplayedMessage

@property (nonatomic) TSInfoMessageType infoMessageType;
@property (nonatomic) TSMessageAdapterType messageType;

#pragma mark - Initialization

- (instancetype)initWithInfoType:(TSInfoMessageType)messageType
                        senderId:(NSString *)senderId
               senderDisplayName:(NSString *)senderDisplayName
                            date:(NSDate *)date;

- (NSString *)text;

@end
