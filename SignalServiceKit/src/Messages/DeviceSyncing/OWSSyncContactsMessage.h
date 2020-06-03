//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "OWSOutgoingSyncMessage.h"

NS_ASSUME_NONNULL_BEGIN

@protocol ProfileManagerProtocol;

@class OWSIdentityManager;
@class SDSAnyReadTransaction;
@class SignalAccount;

@interface OWSSyncContactsMessage : OWSOutgoingSyncMessage

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithThread:(TSThread *)thread NS_UNAVAILABLE;
- (instancetype)initWithTimestamp:(uint64_t)timestamp thread:(TSThread *)thread NS_UNAVAILABLE;

- (instancetype)initWithThread:(TSThread *)thread
                signalAccounts:(NSArray<SignalAccount *> *)signalAccounts
               identityManager:(OWSIdentityManager *)identityManager
                profileManager:(id<ProfileManagerProtocol>)profileManager NS_DESIGNATED_INITIALIZER;

- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;

- (nullable NSData *)buildPlainTextAttachmentDataWithTransaction:(SDSAnyReadTransaction *)transaction;

@end

NS_ASSUME_NONNULL_END
