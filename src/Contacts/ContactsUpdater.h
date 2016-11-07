//  Created by Frederic Jacobs on 21/11/15.
//  Copyright © 2015 Open Whisper Systems. All rights reserved.

#import "SignalRecipient.h"

NS_ASSUME_NONNULL_BEGIN

@class Contact;

@interface ContactsUpdater : NSObject

#define NOTFOUND_ERROR 777404

+ (instancetype)sharedUpdater;

- (nullable SignalRecipient *)synchronousLookup:(NSString *)identifier error:(NSError **)error;

- (void)lookupIdentifier:(NSString *)identifier
                 success:(void (^)(NSSet<NSString *> *matchedIds))success
                 failure:(void (^)(NSError *error))failure;

- (void)updateSignalContactIntersectionWithABContacts:(NSArray<Contact *> *)abContacts
                                              success:(void (^)())success
                                              failure:(void (^)(NSError *error))failure;
@end

NS_ASSUME_NONNULL_END
