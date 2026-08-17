Pod::Spec.new do |s|
  s.name = 'lynx-app-webview-bridge'
  s.module_name = 'LynxWebViewBridge'
  s.version = '1.0.0'
  s.summary = 'Autolinked module-webview element and native-module bridge.'
  s.homepage = 'https://github.com/lynx-family/lynx'
  s.license = { :type => 'Apache-2.0' }
  s.author = 'Lynx Template'
  s.source = { :path => '..' }
  s.source_files = 'src/**/*.{h,m}'
  s.public_header_files = 'src/**/*.h'
  s.ios.deployment_target = '13.0'
  s.dependency 'Lynx'
  s.dependency 'XElement'
end
