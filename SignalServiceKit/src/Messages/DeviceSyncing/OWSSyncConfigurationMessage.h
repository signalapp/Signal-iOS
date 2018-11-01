//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSOutgoingSyncMessage.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSSyncConfigurationMessage : OWSOutgoingSyncMessage

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithReadReceiptsEnabled:(BOOL)readReceiptsEnabled
         showUnidentifiedDeliveryIndicators:(BOOL)showUnidentifiedDeliveryIndicators
                       showTypingIndicators:(BOOL)showTypingIndicators NS_DESIGNATED_INITIALIZER;

- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
