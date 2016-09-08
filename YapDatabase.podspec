Pod::Spec.new do |s|
  s.name         = "YapDatabase"
  s.version      = "2.9.2"
  s.summary      = "A key/value store built atop sqlite for iOS & Mac."
  s.homepage     = "https://github.com/yapstudios/YapDatabase"
  s.license      = 'MIT'

  s.author = {
    "Robbie Hanson" => "robbiehanson@deusty.com"
  }
  s.source = {
    :git => "https://github.com/yapstudios/YapDatabase.git",
    :tag => s.version.to_s
  }

  s.osx.deployment_target = '10.8'
  s.ios.deployment_target = '6.0'
  s.tvos.deployment_target = '9.0'
  s.watchos.deployment_target = '2.0'

  s.libraries = 'c++'

  s.default_subspecs = 'Standard'

  # There are 2 different versions you can choose from:
  # "Standard" uses the builtin version of sqlite3
  # "SQLCipher" uses a version of sqlite3 compiled with SQLCipher included
  #
  # If you want to encrypt your database, you should choose "SQLCipher"

  s.subspec 'Standard' do |ss|

    ss.subspec 'Core' do |ssc|
      ssc.xcconfig = { 'OTHER_CFLAGS' => '$(inherited) -DYAP_STANDARD_SQLITE' }
      ssc.library = 'sqlite3'
      ssc.dependency 'CocoaLumberjack', '~> 2'
      ssc.source_files = 'YapDatabase/*.{h,m,mm,c}', 'YapDatabase/{Internal,Utilities}/*.{h,m,mm,c}', 'YapDatabase/Extensions/Protocol/**/*.{h,m,mm,c}'
      ssc.private_header_files = 'YapDatabase/Internal/*.h', 'YapDatabase/Extensions/Protocol/Internal/*.h'
    end

    ss.subspec 'Extensions' do |sse|
      sse.dependency 'YapDatabase/Standard/Core'

      sse.subspec 'Views' do |ssee|
        ssee.source_files = 'YapDatabase/Extensions/Views/**/*.{h,m,mm,c}'
        ssee.private_header_files = 'YapDatabase/Extensions/Views/Internal/*.h'
      end

      sse.subspec 'SecondaryIndex' do |ssee|
        ssee.source_files = 'YapDatabase/Extensions/SecondaryIndex/**/*.{h,m,mm,c}'
        ssee.private_header_files = 'YapDatabase/Extensions/SecondaryIndex/Internal/*.h'
      end

      sse.subspec 'CrossProcessNotification' do |ssee|
        ssee.source_files = 'YapDatabase/Extensions/CrossProcessNotification/**/*.{h,m,mm,c}'
        ssee.private_header_files = 'YapDatabase/Extensions/CrossProcessNotification/Internal/*.h'
      end

      sse.subspec 'Relationships' do |ssee|
        ssee.source_files = 'YapDatabase/Extensions/Relationships/**/*.{h,m,mm,c}'
        ssee.private_header_files = 'YapDatabase/Extensions/Relationships/Internal/*.h'
      end

      sse.subspec 'FullTextSearch' do |ssee|
        ssee.source_files = 'YapDatabase/Extensions/FullTextSearch/**/*.{h,m,mm,c}'
        ssee.private_header_files = 'YapDatabase/Extensions/FullTextSearch/Internal/*.h'
      end

      sse.subspec 'Hooks' do |ssee|
        ssee.source_files = 'YapDatabase/Extensions/Hooks/**/*.{h,m,mm,c}'
        ssee.private_header_files = 'YapDatabase/Extensions/Hooks/Internal/*.h'
      end

      sse.subspec 'FilteredViews' do |ssee|
        ssee.dependency 'YapDatabase/Standard/Extensions/Views'
        ssee.source_files = 'YapDatabase/Extensions/FilteredViews/**/*.{h,m,mm,c}'
        ssee.private_header_files = 'YapDatabase/Extensions/FilteredViews/Internal/*.h'
      end

      sse.subspec 'SearchResults' do |ssee|
        ssee.dependency 'YapDatabase/Standard/Extensions/Views'
        ssee.dependency 'YapDatabase/Standard/Extensions/FullTextSearch'
        ssee.source_files = 'YapDatabase/Extensions/SearchResults/**/*.{h,m,mm,c}'
        ssee.private_header_files = 'YapDatabase/Extensions/SearchResults/Internal/*.h'
      end

      sse.subspec 'CloudKit' do |ssee|
        ssee.osx.deployment_target = '10.8'
        ssee.ios.deployment_target = '6.0'
        ssee.tvos.deployment_target = '9.0'
        ssee.source_files = 'YapDatabase/Extensions/CloudKit/**/*.{h,m,mm,c}'
        ssee.private_header_files = 'YapDatabase/Extensions/CloudKit/Internal/*.h'
      end

      sse.subspec 'RTreeIndex' do |ssee|
        ssee.source_files = 'YapDatabase/Extensions/RTreeIndex/**/*.{h,m,mm,c}'
        ssee.private_header_files = 'YapDatabase/Extensions/RTreeIndex/Internal/*.h'
      end

      sse.subspec 'ConnectionProxy' do |ssee|
        ssee.source_files = 'YapDatabase/Extensions/ConnectionProxy/**/*.{h,m,mm,c}'
      end

      sse.subspec 'ActionManager' do |ssee|
        ssee.osx.framework   = 'SystemConfiguration'
        ssee.ios.framework   = 'SystemConfiguration'
        ssee.tvos.framework  = 'SystemConfiguration'
        ssee.dependency 'YapDatabase/Standard/Extensions/Views'
        ssee.source_files = 'YapDatabase/Extensions/ActionManager/**/*.{h,m,mm,c}'
        ssee.private_header_files = 'YapDatabase/Extensions/ActionManager/Internal/*.h'
      end

    end # Extensions

  end #Standard

  # use SQLCipher and enable -DSQLITE_HAS_CODEC flag
  s.subspec 'SQLCipher' do |ss|

    ss.subspec 'Core' do |ssc|
      ssc.xcconfig = { 'OTHER_CFLAGS' => '$(inherited) -DSQLITE_HAS_CODEC' }
      ssc.dependency 'SQLCipher/fts'
      ssc.dependency 'CocoaLumberjack', '~> 2'
      ssc.source_files = 'YapDatabase/*.{h,m,mm,c}', 'YapDatabase/{Internal,Utilities}/*.{h,m,mm,c}', 'YapDatabase/Extensions/Protocol/**/*.{h,m,mm,c}'
      ssc.private_header_files = 'YapDatabase/Internal/*.h', 'YapDatabase/Extensions/Protocol/Internal/*.h'
    end

    ss.subspec 'Extensions' do |sse|
      sse.dependency 'YapDatabase/SQLCipher/Core'

      sse.subspec 'Views' do |ssee|
        ssee.source_files = 'YapDatabase/Extensions/Views/**/*.{h,m,mm,c}'
        ssee.private_header_files = 'YapDatabase/Extensions/Views/Internal/*.h'
      end

      sse.subspec 'SecondaryIndex' do |ssee|
        ssee.source_files = 'YapDatabase/Extensions/SecondaryIndex/**/*.{h,m,mm,c}'
        ssee.private_header_files = 'YapDatabase/Extensions/SecondaryIndex/Internal/*.h'
      end

      sse.subspec 'CrossProcessNotification' do |ssee|
        ssee.source_files = 'YapDatabase/Extensions/CrossProcessNotification/**/*.{h,m,mm,c}'
        ssee.private_header_files = 'YapDatabase/Extensions/CrossProcessNotification/Internal/*.h'
      end

      sse.subspec 'Relationships' do |ssee|
        ssee.source_files = 'YapDatabase/Extensions/Relationships/**/*.{h,m,mm,c}'
        ssee.private_header_files = 'YapDatabase/Extensions/Relationships/Internal/*.h'
      end

      sse.subspec 'FullTextSearch' do |ssee|
        ssee.source_files = 'YapDatabase/Extensions/FullTextSearch/**/*.{h,m,mm,c}'
        ssee.private_header_files = 'YapDatabase/Extensions/FullTextSearch/Internal/*.h'
      end

      sse.subspec 'Hooks' do |ssee|
        ssee.source_files = 'YapDatabase/Extensions/Hooks/**/*.{h,m,mm,c}'
        ssee.private_header_files = 'YapDatabase/Extensions/Hooks/Internal/*.h'
      end

      sse.subspec 'FilteredViews' do |ssee|
        ssee.dependency 'YapDatabase/SQLCipher/Extensions/Views'
        ssee.source_files = 'YapDatabase/Extensions/FilteredViews/**/*.{h,m,mm,c}'
        ssee.private_header_files = 'YapDatabase/Extensions/FilteredViews/Internal/*.h'
      end

      sse.subspec 'SearchResults' do |ssee|
        ssee.dependency 'YapDatabase/SQLCipher/Extensions/Views'
        ssee.dependency 'YapDatabase/SQLCipher/Extensions/FullTextSearch'
        ssee.source_files = 'YapDatabase/Extensions/SearchResults/**/*.{h,m,mm,c}'
        ssee.private_header_files = 'YapDatabase/Extensions/SearchResults/Internal/*.h'
      end

      sse.subspec 'CloudKit' do |ssee|
        ssee.osx.deployment_target = '10.8'
        ssee.ios.deployment_target = '6.0'
        ssee.tvos.deployment_target = '9.0'
        ssee.source_files = 'YapDatabase/Extensions/CloudKit/**/*.{h,m,mm,c}'
        ssee.private_header_files = 'YapDatabase/Extensions/CloudKit/Internal/*.h'
      end

      sse.subspec 'RTreeIndex' do |ssee|
        ssee.source_files = 'YapDatabase/Extensions/RTreeIndex/**/*.{h,m,mm,c}'
        ssee.private_header_files = 'YapDatabase/Extensions/RTreeIndex/Internal/*.h'
      end

      sse.subspec 'ConnectionProxy' do |ssee|
        ssee.source_files = 'YapDatabase/Extensions/ConnectionProxy/**/*.{h,m,mm,c}'
      end

      sse.subspec 'ActionManager' do |ssee|
        ssee.osx.framework   = 'SystemConfiguration'
        ssee.ios.framework   = 'SystemConfiguration'
        ssee.tvos.framework  = 'SystemConfiguration'
        ssee.dependency 'YapDatabase/SQLCipher/Extensions/Views'
        ssee.source_files = 'YapDatabase/Extensions/ActionManager/**/*.{h,m,mm,c}'
        ssee.private_header_files = 'YapDatabase/Extensions/ActionManager/Internal/*.h'
      end

    end # Extensions

  end # SQLCipher

end
