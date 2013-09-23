YapDatabase
===========

YapDatabase is a "Key/Value Store and More" built atop sqlite for iOS & Mac.
It has the following features:

* **Concurrency**. You can read from the database while another thread is simultaneously making modifications to the database. So you never have to worry about blocking the main thread, and you can easily write to the database on a background thread. And, of course, you can read from the database on multiple threads simultaneously.

* **Built-In Caching**. A configurable object cache is built-in. Of course sqlite has caching too. But it's caching raw bytes, and we're dealing with objects. So having a built-in cache means you can skip the deserialization process, and get your objects even faster.

* **Collections**. Sometimes a single key isn't enough. Sometimes a collection & key is better. No worries. We've got a database for that.

* **Metadata**. Ever wanted to store extra data along with your object? Like maybe a timestamp of when it was downloaded. Or a fully separate but related object? You're in luck. Metadata support comes standard. Along with its own separate configurable cache too!
 
* **Extensions**. More than just a key/value store, YapDatabase comes with an extensions architecture built-in. Version 2.0 ships with Views. Coming soon: Full Text Search, Secondary Indexing, R-Trees.
 
* **Performance**. Fetch thousands of objects on the main thread without dropping a frame.

* **Objective-C**. A simple to use Objective-C API means you'll be up and running in no time.

<br/>

**[See what the API looks like in "hello world" for YapDatabase](https://github.com/yaptv/YapDatabase/wiki/Hello-World)**<br/>
**[Learn more by visiting the wiki](https://github.com/yaptv/YapDatabase/wiki)**<br/>
