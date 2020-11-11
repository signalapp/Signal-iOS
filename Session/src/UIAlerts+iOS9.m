//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import <objc/runtime.h>

@implementation UIAlertController (iOS9)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // On iOS9, avoids an exception when presenting an alert controller.
        //
        // *** Assertion failure in -[UIAlertController supportedInterfaceOrientations], /BuildRoot/Library/Caches/com.apple.xbs/Sources/UIKit/UIKit-3512.30.14/UIAlertController.m:542
        // Terminating app due to uncaught exception 'NSInternalInconsistencyException', reason: 'UIAlertController:supportedInterfaceOrientations was invoked recursively!'
        //
        // I'm not sure when this was introduced, or the exact root casue, but this quick workaround
        // seems reasonable given the small size of our iOS9 userbase.
        if (@available(iOS 10, *)) {
            return;
        }

        Class class = [self class];

        // supportedInterfaceOrientation

        SEL originalOrientationSelector = @selector(supportedInterfaceOrientations);
        SEL swizzledOrientationSelector = @selector(ows_iOS9Alerts_swizzle_supportedInterfaceOrientation);

        Method originalOrientationMethod = class_getInstanceMethod(class, originalOrientationSelector);
        Method swizzledOrientationMethod = class_getInstanceMethod(class, swizzledOrientationSelector);

        BOOL didAddOrientationMethod = class_addMethod(class,
                                            originalOrientationSelector,
                                            method_getImplementation(swizzledOrientationMethod),
                                            method_getTypeEncoding(swizzledOrientationMethod));

        if (didAddOrientationMethod) {
            class_replaceMethod(class,
                                swizzledOrientationSelector,
                                method_getImplementation(originalOrientationMethod),
                                method_getTypeEncoding(originalOrientationMethod));
        } else {
            method_exchangeImplementations(originalOrientationMethod, swizzledOrientationMethod);
        }

        // shouldAutorotate

        SEL originalAutorotateSelector = @selector(shouldAutorotate);
        SEL swizzledAutorotateSelector = @selector(ows_iOS9Alerts_swizzle_shouldAutorotate);

        Method originalAutorotateMethod = class_getInstanceMethod(class, originalAutorotateSelector);
        Method swizzledAutorotateMethod = class_getInstanceMethod(class, swizzledAutorotateSelector);

        BOOL didAddAutorotateMethod = class_addMethod(class,
                                                       originalAutorotateSelector,
                                                       method_getImplementation(swizzledAutorotateMethod),
                                                       method_getTypeEncoding(swizzledAutorotateMethod));

        if (didAddAutorotateMethod) {
            class_replaceMethod(class,
                                swizzledAutorotateSelector,
                                method_getImplementation(originalAutorotateMethod),
                                method_getTypeEncoding(originalAutorotateMethod));
        } else {
            method_exchangeImplementations(originalAutorotateMethod, swizzledAutorotateMethod);
        }
    });
}

#pragma mark - Method Swizzling

- (UIInterfaceOrientationMask)ows_iOS9Alerts_swizzle_supportedInterfaceOrientation
{
    OWSLogInfo(@"swizzled");
    return UIInterfaceOrientationMaskAllButUpsideDown;
}

- (BOOL)ows_iOS9Alerts_swizzle_shouldAutorotate
{
    OWSLogInfo(@"swizzled");
    return NO;
}

@end
