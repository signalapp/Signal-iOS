//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import <YapDatabase/YapDatabaseViewTransaction.h>

NS_ASSUME_NONNULL_BEGIN

@interface YapDatabaseViewTransaction (OWS)

- (void)safe_enumerateKeysAndObjectsInGroup:(NSString *)group
                              extensionName:(NSString *)extensionName
                                withOptions:(NSEnumerationOptions)options
                                 usingBlock:(void (^)(NSString *collection,
                                                NSString *key,
                                                id object,
                                                NSUInteger index,
                                                BOOL *stop))block;

@end

NS_ASSUME_NONNULL_END
