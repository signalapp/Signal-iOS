//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

typedef void (^OWSItemProviderDataCompletionHandler)(NSData *_Nullable data, NSError *_Nullable error);

@implementation NSItemProvider (OWS)

- (void)loadItemForTypeIdentifier:(NSString *)typeIdentifier options:(nullable NSDictionary *)options dataCompletionHandler:(nullable OWSItemProviderDataCompletionHandler)completionHandler;

@end
