Pod::Spec.new do |s|
  s.name = "MapConductorForTemplate"
  s.version = "1.2.0"
  s.summary = "MapConductor's driver template (not a real map provider)."
  # 他のプロバイダは LICENSE ファイルを持つが、この雛形は ios-sdk 本体に同梱されていて
  # 単体で配布しないので、テキストを直接置く。
  s.license = { :type => "Apache-2.0", :text => "Copyright MapConductor. Licensed under the Apache License, Version 2.0." }
  s.author = "MapConductor"
  s.homepage = "https://github.com/MapConductor/ios-sdk"
  s.source = { :path => __dir__ }
  s.platform = :ios, "16.0"
  s.swift_version = "5.9"
  s.source_files = "Sources/MapConductorForTemplate/**/*.swift"
  s.dependency "MapConductorCore"
  # 本物のドライバーはここに地図SDKの依存を足す（`s.dependency "MapLibre", "~> 6.20"` 等）。
  # 雛形の地図は描画面を持たない代役なので、ベンダ依存は無い。
end
