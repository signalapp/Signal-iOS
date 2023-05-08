//
// Copyright 2014 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

NS_ASSUME_NONNULL_BEGIN

#ifdef USE_DEBUG_UI

@class CNContact;

@interface DebugContactsUtils : NSObject

+ (NSString *)randomPhoneNumber;

+ (void)createRandomContacts:(NSUInteger)count;

+ (void)createRandomContacts:(NSUInteger)count
              contactHandler:
                  (nullable void (^)(CNContact *_Nonnull contact, NSUInteger idx, BOOL *_Nonnull stop))contactHandler;

+ (void)deleteAllContacts;

+ (void)deleteAllRandomContacts;

@end

#endif

NS_ASSUME_NONNULL_END
