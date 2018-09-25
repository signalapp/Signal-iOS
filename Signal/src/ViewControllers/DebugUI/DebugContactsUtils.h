//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

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

NS_ASSUME_NONNULL_END
