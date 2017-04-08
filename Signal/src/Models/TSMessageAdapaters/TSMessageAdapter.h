//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSMessageData.h"
#import "OWSMessageEditing.h"
#import "TSInfoMessage.h"
#import "ContactsManagerProtocol.h"

NS_ASSUME_NONNULL_BEGIN

@class TSInteraction;
@class TSThread;

#define ME_MESSAGE_IDENTIFIER @"Me";

@interface TSMessageAdapter : NSObject <OWSMessageData>

+ (id<OWSMessageData>)messageViewDataWithInteraction:(TSInteraction *)interaction inThread:(TSThread *)thread contactsManager:(id<ContactsManagerProtocol>)contactsManager;

@property (nonatomic) TSInteraction *interaction;
@property (readonly) TSInfoMessageType infoMessageType;
@property (nonatomic, readonly) CGFloat mediaViewAlpha;
@property (nonatomic, readonly) BOOL isMediaBeingSent;
@property (nonatomic, readonly) BOOL isOutgoingAndDelivered;

@end

NS_ASSUME_NONNULL_END
