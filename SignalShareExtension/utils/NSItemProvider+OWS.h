//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

typedef void (^OWSItemProviderDataCompletionHandler)(NSData *_Nullable data, NSError *_Nullable error);


@interface NSItemProvider (OWS)

- (void)loadItemForTypeIdentifier:(NSString *)typeIdentifier options:(nullable NSDictionary *)options dataCompletionHandler:(nullable OWSItemProviderDataCompletionHandler)completionHandler;

@end

NS_ASSUME_NONNULL_END
