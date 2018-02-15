//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "NSItemProvider+OWS.h"

NS_ASSUME_NONNULL_BEGIN

@implementation NSItemProvider (OWS)

- (void)loadDataForTypeIdentifier:(NSString *)typeIdentifier
                          options:(nullable NSDictionary *)options
                completionHandler:(nullable NSItemProviderCompletionHandler)completionHandler
{
    [self loadItemForTypeIdentifier:typeIdentifier
                            options:options
                  completionHandler:^(NSData *_Nullable item, NSError *__null_unspecified error) {
                      completionHandler(item, error);
                  }];
}

@end

NS_ASSUME_NONNULL_END
