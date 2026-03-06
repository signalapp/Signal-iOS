//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <Foundation/Foundation.h>

//! Project version number for SignalServiceKit.
FOUNDATION_EXPORT double SignalServiceKitVersionNumber;

//! Project version string for SignalServiceKit.
FOUNDATION_EXPORT const unsigned char SignalServiceKitVersionString[];

#import <SignalServiceKit/BaseModel.h>
#import <SignalServiceKit/DebuggerUtils.h>
#import <SignalServiceKit/OWSAddToContactsOfferMessage.h>
#import <SignalServiceKit/OWSAddToProfileWhitelistOfferMessage.h>
#import <SignalServiceKit/OWSArchivedPaymentMessage.h>
#import <SignalServiceKit/OWSAsserts.h>
#import <SignalServiceKit/OWSDisappearingConfigurationUpdateInfoMessage.h>
#import <SignalServiceKit/OWSGroupCallMessage.h>
#import <SignalServiceKit/OWSIncomingArchivedPaymentMessage.h>
#import <SignalServiceKit/OWSIncomingPaymentMessage.h>
#import <SignalServiceKit/OWSLogs.h>
#import <SignalServiceKit/OWSOutgoingArchivedPaymentMessage.h>
#import <SignalServiceKit/OWSOutgoingPaymentMessage.h>
#import <SignalServiceKit/OWSPaymentMessage.h>
#import <SignalServiceKit/OWSReadTracking.h>
#import <SignalServiceKit/OWSRecoverableDecryptionPlaceholder.h>
#import <SignalServiceKit/OWSUnknownContactBlockOfferMessage.h>
#import <SignalServiceKit/OWSUnknownProtocolVersionMessage.h>
#import <SignalServiceKit/OWSVerificationState.h>
#import <SignalServiceKit/OWSVerificationStateChangeMessage.h>
#import <SignalServiceKit/SSKAccessors+SDS.h>
#import <SignalServiceKit/TSCall.h>
#import <SignalServiceKit/TSErrorMessage.h>
#import <SignalServiceKit/TSGroupModel.h>
#import <SignalServiceKit/TSIncomingMessage.h>
#import <SignalServiceKit/TSInfoMessage.h>
#import <SignalServiceKit/TSInteraction.h>
#import <SignalServiceKit/TSInvalidIdentityKeyErrorMessage.h>
#import <SignalServiceKit/TSInvalidIdentityKeyReceivingErrorMessage.h>
#import <SignalServiceKit/TSInvalidIdentityKeySendingErrorMessage.h>
#import <SignalServiceKit/TSMessage.h>
#import <SignalServiceKit/TSOutgoingMessage.h>
#import <SignalServiceKit/TSPaymentModels.h>
#import <SignalServiceKit/TSQuotedMessage.h>
#import <SignalServiceKit/TSUnreadIndicatorInteraction.h>
#import <SignalServiceKit/TSYapDatabaseObject.h>
#import <SignalServiceKit/Threading.h>

#define OWSLocalizedString(key, comment)                                                                               \
    [[NSBundle mainBundle].appBundle localizedStringForKey:(key) value:@"" table:nil]
