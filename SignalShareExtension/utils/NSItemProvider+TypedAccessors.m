//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
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

- (void)ows_loadAttributedTextForTypeIdentifier:(NSString *)typeIdentifier
                                        options:(nullable NSDictionary *)options
                              completionHandler:(void (^_Nullable)(
                                                    NSAttributedString *_Nullable, NSError *_Nullable))completionHandler
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
