//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <SignalServiceKit/OWSOutgoingSyncMessage.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSSyncConfigurationMessage : OWSOutgoingSyncMessage

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithLocalThread:(TSContactThread *)localThread
                        transaction:(DBReadTransaction *)transaction NS_UNAVAILABLE;
- (instancetype)initWithTimestamp:(uint64_t)timestamp
                      localThread:(TSContactThread *)localThread
                      transaction:(DBReadTransaction *)transaction NS_UNAVAILABLE;

- (instancetype)initWithLocalThread:(TSContactThread *)localThread
                   readReceiptsEnabled:(BOOL)readReceiptsEnabled
    showUnidentifiedDeliveryIndicators:(BOOL)showUnidentifiedDeliveryIndicators
                  showTypingIndicators:(BOOL)showTypingIndicators
                      sendLinkPreviews:(BOOL)sendLinkPreviews
                   provisioningVersion:(uint32_t)provisioningVersion
                           transaction:(DBReadTransaction *)transaction NS_DESIGNATED_INITIALIZER;

- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
