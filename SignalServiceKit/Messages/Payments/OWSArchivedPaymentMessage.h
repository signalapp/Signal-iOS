//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <SignalServiceKit/TSPaymentModels.h>

#ifndef OWSRestoredPayment_h
#define OWSRestoredPayment_h

@protocol OWSArchivedPaymentMessage
@required
@property (nonatomic, readonly) TSArchivedPaymentInfo *archivedPaymentInfo;
@end

#endif /* OWSRestoredPayment_h */
