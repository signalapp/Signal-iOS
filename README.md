![YapDatabaseLogo](https://user-images.githubusercontent.com/449168/27611211-2570fbb6-5b46-11e7-85e9-f3378a5bebce.gif)
[![Build Status](https://travis-ci.org/yapstudios/YapDatabase.svg?branch=master)](https://travis-ci.org/yapstudios/YapDatabase)
[![Pod Version](https://img.shields.io/cocoapods/v/YapDatabase.svg?style=flat)](https://cocoapods.org/pods/YapDatabase)
[![Carthage compatible](https://img.shields.io/badge/Carthage-compatible-4BC51D.svg?style=flat)](https://github.com/Carthage/Carthage)

YapDatabase is a "**key/value store and MUCH MORE**" built atop sqlite for iOS & Mac.
It has the following features:

* **Concurrency**. You can read from the database while another thread is simultaneously making modifications to the database. So you never have to worry about blocking the main thread, and you can easily write to the database on a background thread. And, of course, you can read from the database on multiple threads simultaneously.

* **Built-In Caching**. A configurable object cache is built-in. Of course sqlite has caching too. But it's caching raw serialized bytes, and we're dealing with objects. So having a built-in cache means you can skip the deserialization process, and get your objects much faster.

* **Collections**. Sometimes a single key isn't enough. Sometimes a collection & key is better. No worries. YapDatabase supports collections out of the box.

* **Metadata**. Ever wanted to store extra data along with your object? Like maybe a timestamp of when it was downloaded. Or a fully separate but related object? You're in luck. Metadata support comes standard. Along with its own separate configurable cache too!

* **Views**. Need to filter, group & sort your data? No problem. YapDatabase comes with Views. And you don't even need to write esoteric SQL queries. Views work using blocks with your own code. Plus they automatically update themselves, and they make animating tables super easy.
 
* **Secondary Indexing**. Speed up your queries by indexing important properties. And then use SQL style queries to quickly find your items.

* **Full Text Search**. Built atop sqlite's FTS module (contributed by google), you can add extremely speedy searching to your app with minimal effort.

* **Relationships**. You can setup relationships between objects and even configure cascading delete rules.

* **Sync**. Support for syncing with Apple's CloudKit is available out of the box. There's even a fully functioning example project that demonstrates writing a syncing Todo app.

* **Extensions**. More than just a key/value store, YapDatabase comes with an extensions architecture built-in. You can even create your own extensions.
 
* **Performance**. Fetch thousands of objects on the main thread without dropping a frame.

* **Objective-C**. A simple to use Objective-C API means you'll be up and running in no time.

<br/>

**[See what the API looks like in "hello world" for YapDatabase](https://github.com/yapstudios/YapDatabase/wiki/Hello-World)**<br/>
**[Learn more by visiting the wiki](https://github.com/yapstudios/YapDatabase/wiki)**<br/>
