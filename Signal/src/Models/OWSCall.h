//  Created by Dylan Bourgeois on 20/11/14.
//  Portions Copyright (c) 2016 Open Whisper Systems. All rights reserved.

#import "TSMessageAdapter.h"
#import <Foundation/Foundation.h>
#import <JSQMessagesViewController/JSQMessageData.h>

typedef enum : NSUInteger {
    kCallOutgoing = 1,
    kCallIncoming = 2,
    kCallMissed = 3,
    kGroupUpdateJoin = 4,
    kGroupUpdateLeft = 5,
    kGroupUpdate = 6
} CallStatus;


@interface OWSCall : NSObject <JSQMessageData, NSCoding, NSCopying>

/*
 * Returns the string Id of the user who initiated the call
 */
@property (copy, nonatomic, readonly) NSString *senderId;


/*
 * Returns the display name for user who initiated the call
 */
@property (copy, nonatomic, readonly) NSString *senderDisplayName;

/*
 * Returns date of the call
 */
@property (copy, nonatomic, readonly) NSDate *date;

/*
 * Returns the call status
 * @see CallStatus
 */
@property (nonatomic) CallStatus status;

/*
 * Returns message type for adapter
 */
@property (nonatomic) TSMessageAdapterType messageType;

/*
 * User can configure whether a thumbnail is used in the display of this cell or not
 */
@property (nonatomic) BOOL useThumbnail;

/**
 *  String to be displayed
 */

@property (nonatomic, copy) NSString *detailString;


#pragma mark - Initialization

- (instancetype)initWithCallerId:(NSString *)callerId
               callerDisplayName:(NSString *)callerDisplayName
                            date:(NSDate *)date
                          status:(CallStatus)status
                   displayString:(NSString *)detailString;

- (NSString *)dateText;

- (UIImage *)thumbnailImage;

@end
