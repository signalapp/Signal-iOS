//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface AVAudioSession (OWS)

// #RADAR 45397675 http://www.openradar.me/45397675
//
// A bug in Swift 4.2+ made `AVAudioSession#setCategory:categorywithOptions:error` not accessible
// to Swift.
//
// It's still available via ObjC, so we have an objc-category method which we can call from Swift
// which just calls the original `AVAudioSession#setCategory:categorywithOptions:error` method.
- (BOOL)ows_setCategory:(AVAudioSessionCategory)category withOptions:(AVAudioSessionCategoryOptions)options error:(NSError **)outError API_AVAILABLE(ios(6.0), watchos(2.0), tvos(9.0)) API_UNAVAILABLE(macos);

@end

NS_ASSUME_NONNULL_END
