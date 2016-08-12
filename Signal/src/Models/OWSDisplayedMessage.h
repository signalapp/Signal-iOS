//  Created by Dylan Bourgeois on 29/11/14.
//  Copyright (c) 2014 Hexed Bits. All rights reserved.
//  Portions Copyright (c) 2016 Open Whisper Systems. All rights reserved.

#import "JSQMessageData.h"
#import <Foundation/Foundation.h>

/* OWSDisplayedMessage message is the parent class for displaying information to the user
 * from within the conversation view. Do not use directly :
 *
 * @see OWSInfoMessage
 * @see OWSErrorMessage
 *
 */
@interface OWSDisplayedMessage : NSObject <JSQMessageData>

/*
 * Returns the unique identifier of the person affected by the displayed message
 */
@property (copy, nonatomic, readonly) NSString *senderId;

/*
 * Returns the name of the person affected by the displayed message
 */
@property (copy, nonatomic, readonly) NSString *senderDisplayName;

/*
 * Returns date of the displayed message
 */
@property (copy, nonatomic, readonly) NSDate *date;

#pragma mark - Initializer

- (instancetype)initWithSenderId:(NSString *)senderId
               senderDisplayName:(NSString *)senderDisplayName
                            date:(NSDate *)date;

@end
