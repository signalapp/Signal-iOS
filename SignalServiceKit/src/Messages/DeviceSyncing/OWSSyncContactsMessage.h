//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSOutgoingSyncMessage.h"

NS_ASSUME_NONNULL_BEGIN

@protocol ContactsManagerProtocol;
@protocol ProfileManagerProtocol;
@class OWSIdentityManager;

@interface OWSSyncContactsMessage : OWSOutgoingSyncMessage

- (instancetype)initWithContactsManager:(id<ContactsManagerProtocol>)contactsManager
                        identityManager:(OWSIdentityManager *)identityManager
                         profileManager:(id<ProfileManagerProtocol>)profileManager;

- (NSData *)buildPlainTextAttachmentData;

@end

NS_ASSUME_NONNULL_END
