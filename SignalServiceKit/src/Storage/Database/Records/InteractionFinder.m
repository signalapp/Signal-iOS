//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "InteractionFinder.h"

NS_ASSUME_NONNULL_BEGIN

@implementation YapDatabaseViewTransaction (OWS)

- (void)safe_enumerateKeysAndObjectsInGroup:(NSString *)group
                           withOptions:(NSEnumerationOptions)options
                            usingBlock:
(void (^)(NSString *collection, NSString *key, id object, NSUInteger index, BOOL *stop))block {

    if (group.length < 1) {
        OWSFail(@"Invalid group.");
        return;
    }

    [self enumerateKeysAndObjectsInGroup:group
                             withOptions:options
                              usingBlock:^(NSString *collection, NSString *key, id object, NSUInteger index, BOOL *stop) {
                                  if (collection.length < 1) {
                                      OWSFail(@"Invalid collection.");
                                      return;
                                  }
                                  if (key.length < 1) {
                                      OWSFail(@"Invalid key.");
                                      return;
                                  }
                                  if (object == nil) {
                                      OWSFail(@"Invalid object.");
                                      return;
                                  }
                                  if (stop == nil) {
                                      OWSFail(@"Invalid stop.");
                                      return;
                                  }

                                  block(collection, key, object, index, stop);
                              }];
}

@end

NS_ASSUME_NONNULL_END
