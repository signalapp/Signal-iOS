Pod::Spec.new do |s|
  s.name               = "blurhash"
  s.version            = "0.0.1"
  s.summary            = "A very compact representation of a placeholder for an image."
  s.description        = "A pure-Swift library for generating and decoding very compact image placeholders."
  s.homepage           = "https://github.com/woltapp/blurhash"
  s.license            = { :type => "MIT", :file => "Swift/License.txt" }
  s.author             = { "Dag Ågren" => "paracelsus@gmail.com" }
  s.social_media_url   = "https://github.com/woltapp"
  s.swift_versions     = ["5"]
  s.source             = { :git => "https://github.com/woltapp/blurhash.git", :commit => "0a1f97898d9eb8952bc528cd7a8ec73d9fecf5d0" }
  s.source_files       = "Swift/*.swift"
end
