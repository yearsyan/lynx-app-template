Pod::Spec.new do |s|
  s.name = 'lynx-app-storage'
  s.version = '1.0.0'
  s.summary = 'Autolinked MMKV-backed KV store and secure storage module for Lynx hosts.'
  s.homepage = 'https://github.com/lynx-family/lynx'
  s.license = { :type => 'Apache-2.0' }
  s.author = 'Lynx Template'
  s.source = { :path => '..' }
  s.source_files = 'src/**/*.{h,m}'
  s.ios.deployment_target = '13.0'
  s.framework = 'Security'
  s.dependency 'Lynx'
  s.dependency 'MMKV', '2.4.1'
end
