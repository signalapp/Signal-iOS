//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import XCTest

/////
// Swift Test vs. CocoaPods issue #1
/////
//
// CocoaPods-generated test targets (like this one)
// fail to link if:
//
// * They only contain Obj-C tests.
// * They depend on pods that use Swift.
//
// The work around is to add (this) empty swift file
// to our test target.
//
// See: https://github.com/CocoaPods/CocoaPods/issues/7170

/////
// Swift Test vs. CocoaPods issue #2
/////
//
// XCode's test runner doesn't copy swift framework's required by dependencies into
// the running test bundle.
// It sounds similar to this issue: https://github.com/CocoaPods/CocoaPods/issues/7985
//
// The error output looks like this:
//     The bundle “SignalServiceKit-Unit-Tests” couldn’t be loaded because it is damaged or missing necessary resources. Try reinstalling the bundle.
//         [...]/SignalServiceKit-Unit-Tests.xctest/SignalServiceKit-Unit-Tests): Library not loaded: @rpath/libswiftAVFoundation.dylib
//       Referenced from: /Users/[...]/Build/Products/Debug-iphonesimulator/SignalServiceKit/SignalServiceKit.framework/SignalServiceKit
//       Reason: image not found)
//     Program ended with exit code: 82
//
// A work around is to redundantly import any swift frameworks used by the dependencies of the test suite into this test file.
// The error message provides a hint, i.e. "Library not loaded: @rpath/libswiftAVFoundation.dylib" is fixed with `import AVFoundation`
import AVFoundation
import CloudKit
