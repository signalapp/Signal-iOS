//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSAvatarBuilder.h"

NS_ASSUME_NONNULL_BEGIN

@class OWSContactsManager;
@class TSContactThread;

@interface OWSContactAvatarBuilder : OWSAvatarBuilder

- (instancetype)initWithContactId:(NSString *)contactId
                             name:(NSString *)name
                  contactsManager:(OWSContactsManager *)contactsManager;

- (instancetype)initWithContactId:(NSString *)contactId
                             name:(NSString *)name
                  contactsManager:(OWSContactsManager *)contactsManager
                         diameter:(NSUInteger)diameter;

- (instancetype)initWithThread:(TSContactThread *)thread
               contactsManager:(OWSContactsManager *)contactsManager
                      diameter:(NSUInteger)diameter;

- (instancetype)initWithThread:(TSContactThread *)thread contactsManager:(OWSContactsManager *)contactsManager;

@end

NS_ASSUME_NONNULL_END
