//
//  JSQInfoMessage.h
//  JSQMessages
//
//  Created by Dylan Bourgeois on 29/11/14.
//  Copyright (c) 2014 Hexed Bits. All rights reserved.
//

#import "JSQDisplayedMessage.h"

typedef NS_ENUM(NSInteger, JSQInfoMessageType){
    JSQInfoMessageTypeSessionDidEnd,
};

@interface JSQInfoMessage : JSQDisplayedMessage

@property (nonatomic) JSQInfoMessageType infoMessageType;

@property (nonatomic) TSMessageAdapterType messageType;

#pragma mark - Initialization

- (instancetype)initWithInfoType:(JSQInfoMessageType)messageType
                        senderId:(NSString*)senderId
               senderDisplayName:(NSString*)senderDisplayName
                            date:(NSDate*)date;

- (NSString*)text;


@end
