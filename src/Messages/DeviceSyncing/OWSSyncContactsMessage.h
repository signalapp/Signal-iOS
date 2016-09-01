//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "OWSOutgoingSyncMessage.h"

NS_ASSUME_NONNULL_BEGIN

@class YapDatabaseReadWriteTransaction;
@protocol ContactsManagerProtocol;

@interface OWSSyncContactsMessage : OWSOutgoingSyncMessage

- (instancetype)initWithContactsManager:(id<ContactsManagerProtocol>)contactsManager;
- (NSData *)buildPlainTextAttachmentData;

@end

NS_ASSUME_NONNULL_END
