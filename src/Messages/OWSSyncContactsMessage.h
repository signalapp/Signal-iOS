//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "ContactsManagerProtocol.h"
#import "OWSOutgoingSyncMessage.h"

@interface OWSSyncContactsMessage : OWSOutgoingSyncMessage

- (instancetype)initWithContactsManager:(id<ContactsManagerProtocol>)contactsManager;
- (void)saveWithTransaction:(YapDatabaseReadWriteTransaction *)transaction;
- (NSData *)buildPlainTextAttachmentData;

@end
