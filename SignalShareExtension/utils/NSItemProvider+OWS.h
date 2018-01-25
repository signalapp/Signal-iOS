//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@interface NSItemProvider (OWS)

// NSItemProvider.loadItem(forTypeIdentifier:...) is unsafe to call from Swift,
// since it can yield values of arbitrary type.  It has a highly unusual design
// in which its behavior depends on the _type_ of the completion handler.
// loadItem(forTypeIdentifier:...) tries to satisfy the expected type of the
// completion handler.  This "hinting" only works in Objective-C.  In Swift,
// The type of the completion handler must agree with the param type.
//
// Therefore we use an Objective-C category to hint to NSItemProvider that we
// prefer an instance of NSData.
//
// See: https://developer.apple.com/documentation/foundation/nsitemprovider/1403900-loaditemfortypeidentifier
- (void)loadDataForTypeIdentifier:(NSString *)typeIdentifier
                          options:(nullable NSDictionary *)options
                completionHandler:(nullable NSItemProviderCompletionHandler)completionHandler;

@end

NS_ASSUME_NONNULL_END
