Pod::Spec.new do |s|
  s.name = 'lynx-app-scanner'
  s.version = '1.0.0'
  s.summary = 'Autolinked QR and barcode scanning module for Lynx hosts.'
  s.homepage = 'https://github.com/lynx-family/lynx'
  s.license = { :type => 'Apache-2.0' }
  s.author = 'Lynx Template'
  s.source = { :path => '..' }
  s.source_files = 'src/**/*.{h,m}'
  s.ios.deployment_target = '13.0'
  s.requires_arc = true
  s.frameworks = 'AVFoundation', 'CoreGraphics', 'CoreImage', 'CoreVideo',
                 'ImageIO', 'UIKit', 'Vision'
  s.dependency 'Lynx'
end
