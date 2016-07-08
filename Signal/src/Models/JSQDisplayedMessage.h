//
//  JSQDisplayedMessage.h
//  JSQMessages
//
//  Created by Dylan Bourgeois on 29/11/14.
//  Copyright (c) 2014 Hexed Bits. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "JSQMessageData.h"
#import "TSMessageAdapter.h"

/* JSQDisplayed message is the parent class for displaying information to the user
 * from within the conversation view. Do not use directly :
 *
 * @see JSQInfoMessage
 * @see JSQErrorMessage
 *
 */

@interface JSQDisplayedMessage : NSObject <JSQMessageData>

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

-(instancetype)initWithSenderId:(NSString*)senderId
              senderDisplayName:(NSString*)senderDisplayName
                           date:(NSDate*)date;

@end
