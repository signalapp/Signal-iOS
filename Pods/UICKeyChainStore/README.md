# UICKeyChainStore ![License MIT](https://go-shields.herokuapp.com/license-MIT-yellow.png) 

[![Version](https://cocoapod-badges.herokuapp.com/v/UICKeyChainStore/badge.png)](https://cocoapod-badges.herokuapp.com/v/UICKeyChainStore/badge.png)
[![Platform](https://cocoapod-badges.herokuapp.com/p/UICKeyChainStore/badge.png)](https://cocoapod-badges.herokuapp.com/p/UICKeyChainStore/badge.png)
[![Build Status](https://travis-ci.org/kishikawakatsumi/UICKeyChainStore.png?branch=master)](https://travis-ci.org/kishikawakatsumi/UICKeyChainStore)
[![Analytics](https://ga-beacon.appspot.com/UA-4291014-9/UICKeyChainStore/README.md)](https://github.com/igrigorik/ga-beacon)

UICKeyChainStore is a simple wrapper for Keychain on iOS and OS X. Makes using Keychain APIs as easy as NSUserDefaults.


## Installation
### CocoaPods
`pod 'UICKeyChainStore'`

### Manual Install
1. Add `Security.framework` to your target.
2. Copy files in Lib (`UICKeyChainStore.h` and `UICKeyChainStore.m`) to your project.

## Usage

### Using convienient class methods

Add items using default service name (=bundle identifer).

```objective-c
[UICKeyChainStore setString:@"kishikawakatsumi" forKey:@"username"];
[UICKeyChainStore setString:@"password1234" forKey:@"password"];

//=> ["username" = "kishikawakatsumi", "password" = "password1234"]
```

Or specify the service name.

```objective-c
[UICKeyChainStore setString:@"kishikawakatsumi" forKey:@"username" service:@"com.kishikawakatsumi"];
[UICKeyChainStore setString:@"password1234" forKey:@"password" service:@"com.kishikawakatsumi"];
```

---
Remove items.

```objective-c
[UICKeyChainStore removeItemForKey:@"username" service:@"com.kishikawakatsumi"];
[UICKeyChainStore removeItemForKey:@"password" service:@"com.kishikawakatsumi"];
```

=====
### Using store object, easier to edit multiple items

Instantiate store object with default service name.

```objective-c
UICKeyChainStore *store = [UICKeyChainStore keyChainStore];
```

Or specify the service name.

```objective-c
UICKeyChainStore *store = [UICKeyChainStore keyChainStoreWithService:@"com.kishikawakatsumi"];
```

Add items and save.

```objective-c
[store setString:@"kishikawakatsumi@mac.com" forKey:@"username"];
[store setString:@"password1234" forKey:@"password"];

[store synchronize]; // Write to keychain.
```

Remove items.

```objective-c
[store removeItemForKey:@"username"];
[store removeItemForKey:@"password"];

[store synchronize]; // Write to keychain.
```

=====
### Object Subscripting

```objective-c
UICKeyChainStore *store = [UICKeyChainStore keyChainStoreWithService:@"com.kishikawakatsumi"];
```

```objective-c
store[@"username"] = @"kishikawakatsumi@mac.com";
store[@"password"] = @"password1234";
```

```objective-c
[store synchronize];
```

---
### Debug print

```objective-c
UICKeyChainStore *store = [UICKeyChainStore keyChainStoreWithService:@"com.kishikawakatsumi"];
NSLog(@"%@", store); // Print all keys and values for the service.
```

---
Easy as that. (See [UICKeyChainStore.h](https://github.com/kishikawakatsumi/UICKeyChainStore/blob/master/Lib/UICKeyChainStore.h) for all of the methods.)


## License

[Apache]: http://www.apache.org/licenses/LICENSE-2.0
[MIT]: http://www.opensource.org/licenses/mit-license.php
[GPL]: http://www.gnu.org/licenses/gpl.html
[BSD]: http://opensource.org/licenses/bsd-license.php

UICKeyChainStore is available under the [MIT license][MIT]. See the LICENSE file for more info.
