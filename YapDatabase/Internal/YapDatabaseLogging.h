#import <Foundation/Foundation.h>

/**
 * Logging plays a very important role in open-source libraries.
 * 
 * Good documentation and comments decrease the learning time required to use a library.
 * But proper logging takes this futher by:
 * - Providing a way to trace the execution of the library
 * - Allowing developers to quickly identify subsets of the code that need analysis
 * - Making it easier for developers to find potential bugs, either in their code or the library
 * - Drawing attention to potential mis-configurations or mis-uses of the API
 * 
 * Ultimately logging is an interactive extension to comments.
**/

/**
 * Define log levels.
 * YapDatabase uses 4 log levels:
 * 
 * error   - For critical errors that will likely break functionality
 * warn    - For problems that are concerning, but not quite critical
 * info    - For general, but important, information such as performing a database upgrade
 * verbose - For all the other low-level debugging type information
 * 
 * Notice that the levels are actually defined using bitwise flags.
 * This means you have full control to flip individual logs on/off.
 * For example, you could enable errors and info, but not warnings, if you wanted.
**/

#define YDB_LOG_FLAG_ERROR   (1 << 0) // 0...00001
#define YDB_LOG_FLAG_WARN    (1 << 1) // 0...00010
#define YDB_LOG_FLAG_INFO    (1 << 2) // 0...00100
#define YDB_LOG_FLAG_VERBOSE (1 << 3) // 0...01000

#define YDB_LOG_LEVEL_OFF     0                                            // 0...00000
#define YDB_LOG_LEVEL_ERROR   (YDB_LOG_LEVEL_OFF   | YDB_LOG_FLAG_ERROR)   // 0...00001
#define YDB_LOG_LEVEL_WARN    (YDB_LOG_LEVEL_ERROR | YDB_LOG_FLAG_WARN)    // 0...00011
#define YDB_LOG_LEVEL_INFO    (YDB_LOG_LEVEL_WARN  | YDB_LOG_FLAG_INFO)    // 0...00111
#define YDB_LOG_LEVEL_VERBOSE (YDB_LOG_LEVEL_INFO  | YDB_LOG_FLAG_VERBOSE) // 0...01111

#define YDB_LOG_ERROR   (ydbLogLevel & YDB_LOG_FLAG_ERROR)
#define YDB_LOG_WARN    (ydbLogLevel & YDB_LOG_FLAG_WARN)
#define YDB_LOG_INFO    (ydbLogLevel & YDB_LOG_FLAG_INFO)
#define YDB_LOG_VERBOSE (ydbLogLevel & YDB_LOG_FLAG_VERBOSE)

/**
 * Define trace, which is in addition to log levels.
 * It may be turned on/off independent of the log level.
**/

#define YDB_LOG_FLAG_TRACE   (1 << 4) // 0...10000

/**
 * YapDatabase supports multiple logging techniques.
 * 
 * YapDatabase supports the CocoaLumberjack logging framework.
 * This is a professional open-source logging library for Mac and iOS development.
 *
 * If you're not using Lumberjack then you can downgrade to NSLog.
 * You can also completely disable logging throughout the entire library.
 * 
 * You are strongly discouraged from modifying this file.
 * If you do, you make it more difficult on yourself to merge future bug fixes and improvements from the project.
 * Instead, you should override the default values in your own application.
**/

#define YapDatabaseLoggingTechnique_Lumberjack 2 // optimal
#define YapDatabaseLoggingTechnique_NSLog      1 // slower
#define YapDatabaseLoggingTechnique_Disabled   0 // disabled

#ifndef YapDatabaseLoggingTechnique
#define YapDatabaseLoggingTechnique YapDatabaseLoggingTechnique_Lumberjack
#endif

/**
 * CocoaLumberjack has several useful macros and functions.
 * If not using Lumberjack, we re-define these macros for our own use.
**/

#if YapDatabaseLoggingTechnique != YapDatabaseLoggingTechnique_Lumberjack

#ifndef THIS_METHOD
#define THIS_METHOD NSStringFromSelector(_cmd)
#endif

#ifndef THIS_FILE
NSString *YDBExtractFileNameWithoutExtension(const char *filePath);
#define THIS_FILE (YDBExtractFileNameWithoutExtension(__FILE__))
#endif

#endif

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#if (YapDatabaseLoggingTechnique == YapDatabaseLoggingTechnique_Lumberjack)
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// Logging Enabled.
// Logging uses the CocoaLumberjack framework. (optimal)
//
// There is a TON of documentation available from the project page:
// https://github.com/robbiehanson/CocoaLumberjack

#import <CocoaLumberjack/CocoaLumberjack.h>

#define YDBLogAsync   NO
#define YDBLogContext 27017

#define YDBLogMaybe(flg,frmt, ...)   LOG_MAYBE(YDBLogAsync, (DDLogLevel)ydbLogLevel, (DDLogFlag)flg, YDBLogContext, nil, __PRETTY_FUNCTION__, frmt, ##__VA_ARGS__)

#define YDBLogError(frmt, ...)     YDBLogMaybe(YDB_LOG_FLAG_ERROR,   (@"%@: " frmt), THIS_FILE, ##__VA_ARGS__)
#define YDBLogWarn(frmt, ...)      YDBLogMaybe(YDB_LOG_FLAG_WARN,    (@"%@: " frmt), THIS_FILE, ##__VA_ARGS__)
#define YDBLogInfo(frmt, ...)      YDBLogMaybe(YDB_LOG_FLAG_INFO,    (@"%@: " frmt), THIS_FILE, ##__VA_ARGS__)
#define YDBLogVerbose(frmt, ...)   YDBLogMaybe(YDB_LOG_FLAG_VERBOSE, (@"%@: " frmt), THIS_FILE, ##__VA_ARGS__)

#define YDBLogTrace(frmt, ...) YDBLogMaybe(YDB_LOG_FLAG_TRACE, (@"%@: " frmt), THIS_FILE, ##__VA_ARGS__)
#define YDBLogAutoTrace()      YDBLogMaybe(YDB_LOG_FLAG_TRACE,  @"%@: %@",     THIS_FILE, THIS_METHOD)

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#elif (YapDatabaseLoggingTechnique == YapDatabaseLoggingTechnique_NSLog)
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// Logging Enabled.
// Logging uses plain old NSLog. (slower)

#define YDBLogMaybe(flg, frmt, ...) \
    do{ if(ydbLogLevel & flg) NSLog(frmt, ##__VA_ARGS__); } while(0)

#define YDBLogError(frmt, ...)    YDBLogMaybe(YDB_LOG_FLAG_ERROR,   (@"%@: " frmt), THIS_FILE, ##__VA_ARGS__)
#define YDBLogWarn(frmt, ...)     YDBLogMaybe(YDB_LOG_FLAG_WARN,    (@"%@: " frmt), THIS_FILE, ##__VA_ARGS__)
#define YDBLogInfo(frmt, ...)     YDBLogMaybe(YDB_LOG_FLAG_INFO,    (@"%@: " frmt), THIS_FILE, ##__VA_ARGS__)
#define YDBLogVerbose(frmt, ...)  YDBLogMaybe(YDB_LOG_FLAG_VERBOSE, (@"%@: " frmt), THIS_FILE, ##__VA_ARGS__)

#define YDBLogTrace(frmt, ...) YDBLogMaybe(YDB_LOG_FLAG_TRACE, (@"%@: " frmt), THIS_FILE, ##__VA_ARGS__)
#define YDBLogAutoTrace()      YDBLogMaybe(YDB_LOG_FLAG_TRACE,  @"%@: %@",     THIS_FILE, THIS_METHOD)

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#else
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// Logging Disabled

#undef YDB_LOG_ERROR
#undef YDB_LOG_WARN
#undef YDB_LOG_INFO
#undef YDB_LOG_VERBOSE

#define YDB_LOG_ERROR   (NO)
#define YDB_LOG_WARN    (NO)
#define YDB_LOG_INFO    (NO)
#define YDB_LOG_VERBOSE (NO)

#define YDBLogError(frmt, ...)     {}
#define YDBLogWarn(frmt, ...)      {}
#define YDBLogInfo(frmt, ...)      {}
#define YDBLogVerbose(frmt, ...)   {}

#define YDBLogTrace(frmt, ...)     {}
#define YDBLogAutoTrace()          {}

#endif
