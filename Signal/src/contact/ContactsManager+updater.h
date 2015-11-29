//
//  ContactsManager+updater.h
//  Signal
//
//  Created by Frederic Jacobs on 21/11/15.
//  Copyright © 2015 Open Whisper Systems. All rights reserved.
//

#import "SignalRecipient.h"
#import "ContactsManager.h"

@interface ContactsManager (updater)

#define NOTFOUND_ERROR 777404

- (void)intersectContacts;
- (void)synchronousLookup:(NSString*)identifier
                  success:(void (^)(SignalRecipient*))success
                  failure:(void (^)(NSError *error))failure;

- (void)lookupIdentifier:(NSString*)identifier
                 success:(void (^)(NSSet<NSString*> *matchedIds))success
                 failure:(void (^)(NSError *error))failure;

- (void)updateSignalContactIntersectionWithSuccess:(void (^)())success
                                           failure:(void (^)(NSError *error))failure;
@end
