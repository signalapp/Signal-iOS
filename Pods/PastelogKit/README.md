PastelogKit
===========

A simple library that provides an easy fragment allowing users to throw debug logs in a pastebin (currently gist) online, backed by CocoaLumberjack.

## Usage

PasteLogKit is really easy to use. Import `PastelogKit.h` to your source file.

```objective-c
typedef void (^successBlock)(NSError *error, NSString *urlString);

[Pastelog submitLogsWithCompletion:^(NSError *error, *urlString){
  if(error){
    // Process the error;
  } else{
    // email, copy or do something with the gist url
  }
}];
```

If you want to use a specific logger, 

```objective-c 
+(void)submitLogsWithCompletion:(successBlock)block forFileLogger:(DDFileLogger*)fileLogger;
```

## Installation

In your Podfile

```
pod 'PastelogKit', '~> 1.0'
```

## License 

Licensed under the GPLv3: http://www.gnu.org/licenses/gpl-3.0.html
