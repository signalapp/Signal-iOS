//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSOutgoingSyncMessage.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSBlockedPhoneNumbersMessage : OWSOutgoingSyncMessage

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithPhoneNumbers:(NSArray<NSString *> *)phoneNumbers NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
