Pod::Spec.new do |s|
  s.name             = 'Paysio'
  s.version          = '0.1.0'
  s.summary          = 'Paysio Mobile SDK for iOS: card and bank entry, 3-D Secure and checkout in your app.'
  s.description      = <<-DESC
    Take a card or a US bank account natively, run 3-D Secure and complete a Paysio
    checkout session without leaving the app. Card data goes straight from the
    VGS secure fields to the VGS vault; Paysio and your servers only ever see aliases.
  DESC
  s.homepage         = 'https://paysio.com/developers'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Paysio' => 'support@paysio.com' }
  s.source           = { :git => 'https://github.com/Paysio-com/paysio-ios.git', :tag => s.version.to_s }

  s.ios.deployment_target = '16.0'
  s.swift_versions = ['5.9']

  s.source_files = 'Sources/Paysio/**/*.swift'

  s.frameworks = 'UIKit', 'SwiftUI', 'WebKit'

  # VGS Collect iOS SDK (CocoaPods name per VGS docs: pod 'VGSCollectSDK').
  s.dependency 'VGSCollectSDK', '~> 1.20'
end
