//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "SignalRecipient.h"

NS_ASSUME_NONNULL_BEGIN

@class Contact;

@interface ContactsUpdater : NSObject

+ (instancetype)sharedUpdater;

- (nullable SignalRecipient *)synchronousLookup:(NSString *)identifier error:(NSError **)error;

// This asynchronously updates the SignalRecipient for a given contactId.
- (void)lookupIdentifier:(NSString *)identifier
                 success:(void (^)(SignalRecipient *recipient))success
                 failure:(void (^)(NSError *error))failure;

- (void)updateSignalContactIntersectionWithABContacts:(NSArray<Contact *> *)abContacts
                                              success:(void (^)())success
                                              failure:(void (^)(NSError *error))failure;
@end

NS_ASSUME_NONNULL_END
