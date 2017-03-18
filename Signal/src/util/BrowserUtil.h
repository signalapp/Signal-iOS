//
//  Copyright © 2017 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@interface BrowserUtil : NSObject

+ (NSArray *)detectInstalledBrowserNames;

+ (NSDictionary *)schemesForBrowser:(NSString *)browserName;

@end

NS_ASSUME_NONNULL_END
