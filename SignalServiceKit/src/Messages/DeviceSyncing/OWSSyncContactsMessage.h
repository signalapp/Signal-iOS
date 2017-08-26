//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSOutgoingSyncMessage.h"

NS_ASSUME_NONNULL_BEGIN

@protocol ProfileManagerProtocol;
@class SignalAccount;
@class OWSIdentityManager;

@interface OWSSyncContactsMessage : OWSOutgoingSyncMessage

- (instancetype)initWithSignalAccounts:(NSArray<SignalAccount *> *)signalAccounts
                       identityManager:(OWSIdentityManager *)identityManager
                        profileManager:(id<ProfileManagerProtocol>)profileManager;

- (NSData *)buildPlainTextAttachmentData;

@end

NS_ASSUME_NONNULL_END
