//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSOutgoingSyncMessage.h"

NS_ASSUME_NONNULL_BEGIN

@protocol ProfileManagerProtocol;

@class OWSIdentityManager;
@class SDSAnyReadTransaction;
@class SignalAccount;

@interface OWSSyncContactsMessage : OWSOutgoingSyncMessage

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithSignalAccounts:(NSArray<SignalAccount *> *)signalAccounts
                       identityManager:(OWSIdentityManager *)identityManager
                        profileManager:(id<ProfileManagerProtocol>)profileManager NS_DESIGNATED_INITIALIZER;

- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;

- (nullable NSData *)buildPlainTextAttachmentDataWithTransaction:(SDSAnyReadTransaction *)transaction;

@end

NS_ASSUME_NONNULL_END
