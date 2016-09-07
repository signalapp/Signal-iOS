//
//  YapDatabase
//  https://github.com/yapstudios/YapDatabase
//

#if TARGET_OS_WATCH
#import <WatchKit/WatchKit.h>
#elif TARGET_OS_IOS
#import <UIKit/UIKit.h>
#else
#import <Cocoa/Cocoa.h>
#endif

//! Project version number for YapDatabase.
FOUNDATION_EXPORT double YapDatabaseVersionNumber;

//! Project version string for YapDatabase.
FOUNDATION_EXPORT const unsigned char YapDatabaseVersionString[];

// In this header, you should import all the public headers of your framework.
// E.g. #import <YapDatabase/PublicHeader.h>
