//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "TSInfoMessage.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSAddToContactsOfferMessage : TSInfoMessage

+ (instancetype)addToContactsOfferMessage:(uint64_t)timestamp thread:(TSThread *)thread contactId:(NSString *)contactId;

@property (nonatomic, readonly) NSString *contactId;

@end

NS_ASSUME_NONNULL_END
