//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// The value yeiled by NSItemProvider.loadItemForTypeIdentifier depends on the signature of the
/// completion handler you pass in. However, the Swift compiler mandates that the completion handler exactly matches the
/// signature, which yields an NSSecureCoding instance.
///
/// This would generally yeild a usable object (Data, URL, String, etc), but in some cases,
/// e.g. sharing a large PDF from Mail.app, we were yielded an unusable private Apple class.
///
/// To address this, we define a bespoke ObjC method for each type we'd want to be yielded.
@interface NSItemProvider (TypedAccessors)

- (void)ows_loadUrlForTypeIdentifier:(NSString *)typeIdentifier
                             options:(nullable NSDictionary *)options
                   completionHandler:(void (^_Nullable)(NSURL *_Nullable, NSError *_Nullable))completionHandler;

- (void)ows_loadDataForTypeIdentifier:(NSString *)typeIdentifier
                              options:(nullable NSDictionary *)options
                    completionHandler:(void (^_Nullable)(NSData *_Nullable, NSError *_Nullable))completionHandler;

- (void)ows_loadTextForTypeIdentifier:(NSString *)typeIdentifier
                              options:(nullable NSDictionary *)options
                    completionHandler:(void (^_Nullable)(NSString *_Nullable, NSError *_Nullable))completionHandler;

- (void)ows_loadImageForTypeIdentifier:(NSString *)typeIdentifier
                               options:(nullable NSDictionary *)options
                     completionHandler:(void (^_Nullable)(UIImage *_Nullable, NSError *_Nullable))completionHandler;

@end

NS_ASSUME_NONNULL_END
