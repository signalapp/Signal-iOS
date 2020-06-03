//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "NSItemProvider+TypedAccessors.h"

NS_ASSUME_NONNULL_BEGIN

@implementation NSItemProvider (TypedAccessors)

- (void)ows_loadUrlForTypeIdentifier:(NSString *)typeIdentifier
                             options:(nullable NSDictionary *)options
                   completionHandler:(void (^_Nullable)(NSURL *_Nullable, NSError *_Nullable))completionHandler
{
    [self loadItemForTypeIdentifier:typeIdentifier options:options completionHandler:completionHandler];
}

- (void)ows_loadDataForTypeIdentifier:(NSString *)typeIdentifier
                              options:(nullable NSDictionary *)options
                    completionHandler:(void (^_Nullable)(NSData *_Nullable, NSError *_Nullable))completionHandler
{
    [self loadItemForTypeIdentifier:typeIdentifier options:options completionHandler:completionHandler];
}

- (void)ows_loadTextForTypeIdentifier:(NSString *)typeIdentifier
                              options:(nullable NSDictionary *)options
                    completionHandler:(void (^_Nullable)(NSString *_Nullable, NSError *_Nullable))completionHandler
{
    [self loadItemForTypeIdentifier:typeIdentifier options:options completionHandler:completionHandler];
}

- (void)ows_loadImageForTypeIdentifier:(NSString *)typeIdentifier
                               options:(nullable NSDictionary *)options
                     completionHandler:(void (^_Nullable)(UIImage *_Nullable, NSError *_Nullable))completionHandler
{
    [self loadItemForTypeIdentifier:typeIdentifier options:options completionHandler:completionHandler];
}

NS_ASSUME_NONNULL_END

@end
