# Uncomment the next line to define a global platform for your project
platform :ios, '10.0'
source 'https://github.com/CocoaPods/Specs.git'
target 'Paths' do
  # Comment the next line if you're not using Swift and don't want to use dynamic frameworks
  use_frameworks!

  # Pods for Paths
    pod 'GoogleMapsDirections', '~> 1.1'
    pod 'GoogleMaps'
    pod 'GooglePlaces'
    # pod 'Alamofire', '~> 4.5'
    pod 'Charts'
    pod 'Polyline', '~> 4.0'
    # pod 'ObjectMapper', '~> 4.2.0'
    # pod 'Branch'

post_install do |installer|
    installer.pods_project.targets.each do |target|
      target.build_configurations.each do |config|
        config.build_settings['SWIFT_VERSION'] = '4.0'
      end
    end
  end

end
