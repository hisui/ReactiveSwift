Pod::Spec.new do |s|
  s.name     = "ReactiveSwift"
  s.version  = "0.0.1"
  s.summary  = "ReactiveSwift <(^_^;)"
  s.homepage = "https://github.com/hisui/ReactiveSwift"
  s.license  = { :type => "MIT", :file => "LICENSE.txt" }
  s.author   = { "shun" => "findall3@gmail.com" }
  s.source   = { :git => "https://github.com/hisui/ReactiveSwift.git", :tag => "0.0.1" }
  s.source_files = "ReactiveSwift", "ReactiveSwift/*.{h,swift}"
  s.requires_arc = true
  s.frameworks   = "Foundation"
end
