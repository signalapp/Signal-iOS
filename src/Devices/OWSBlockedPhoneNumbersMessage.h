//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSOutgoingSyncMessage.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSBlockedPhoneNumbersMessage : OWSOutgoingSyncMessage

- (instancetype)initWithPhoneNumbers:(NSArray<NSString *> *)phoneNumbers;

@end

NS_ASSUME_NONNULL_END
