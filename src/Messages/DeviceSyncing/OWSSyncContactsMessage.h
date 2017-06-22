//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSOutgoingSyncMessage.h"

NS_ASSUME_NONNULL_BEGIN

@class YapDatabaseReadWriteTransaction;
@protocol ContactsManagerProtocol;
@class OWSIdentityManager;

@interface OWSSyncContactsMessage : OWSOutgoingSyncMessage

- (instancetype)initWithContactsManager:(id<ContactsManagerProtocol>)contactsManager
                        identityManager:(OWSIdentityManager *)identityManager;

- (NSData *)buildPlainTextAttachmentData;

@end

NS_ASSUME_NONNULL_END
