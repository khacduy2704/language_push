require 'xcodeproj'

root = File.expand_path(__dir__)
project = Xcodeproj::Project.new(File.join(root, 'PushLanguage.xcodeproj'))
app = project.new_target(:application, 'PushLanguage', :ios, '15.0')
unit_tests = project.new_target(:unit_test_bundle, 'PushLanguageTests', :ios, '15.0')
ui_tests = project.new_target(:ui_test_bundle, 'PushLanguageUITests', :ios, '15.0')

{
  app => 'PushLanguage',
  unit_tests => 'PushLanguageTests',
  ui_tests => 'PushLanguageUITests'
}.each do |target, directory|
  group = project.main_group.new_group(directory, directory)
  Dir.glob(File.join(root, directory, '**', '*.swift')).sort.each do |path|
    relative_path = path.delete_prefix(File.join(root, directory) + '/')
    target.source_build_phase.add_file_reference(group.new_file(relative_path))
  end

  target.build_configurations.each do |config|
    config.build_settings.merge!(
      'SWIFT_VERSION' => '5.0',
      'TARGETED_DEVICE_FAMILY' => '1,2',
      'GENERATE_INFOPLIST_FILE' => 'YES',
      'PRODUCT_BUNDLE_IDENTIFIER' => "com.example.pushlanguage.native.#{target.name}",
      'CODE_SIGN_STYLE' => 'Automatic'
    )
  end
end

resources = project.main_group.new_group('Dictionary Resources', '../assets/data/EV')
dictionary = resources.new_file('anhviet109K.dict')
dictionary.last_known_file_type = 'text'
app.resources_build_phase.add_file_reference(dictionary)
audio = project.main_group.new_group('Practice Audio', '../assets/audio')
%w[correct.mp3 incorrect.mp3].each do |name|
  app.resources_build_phase.add_file_reference(audio.new_file(name))
end
app.add_system_library('sqlite3')
localizations = project.main_group.new_group('Localizations', 'PushLanguage/Resources')
strings = localizations.new_variant_group('Localizable.strings')
%w[en vi].each do |language|
  file = strings.new_file("#{language}.lproj/Localizable.strings")
  file.name = language
end
project.root_object.known_regions = %w[en vi Base]
app.resources_build_phase.add_file_reference(strings)

firebase = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
firebase.repositoryURL = 'https://github.com/firebase/firebase-ios-sdk.git'
firebase.requirement = { 'kind' => 'exactVersion', 'version' => '11.15.0' }
project.root_object.package_references << firebase
%w[FirebaseCore FirebaseAuth].each do |name|
  dependency = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
  dependency.package = firebase
  dependency.product_name = name
  app.package_product_dependencies << dependency
  build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
  build_file.product_ref = dependency
  app.frameworks_build_phase.files << build_file
end
configuration = File.join(root, 'PushLanguage', 'Configuration', 'GoogleService-Info.plist')
if File.exist?(configuration)
  group = project.main_group.new_group('Firebase Configuration', 'PushLanguage/Configuration')
  app.resources_build_phase.add_file_reference(group.new_file('GoogleService-Info.plist'))
end

app.build_configurations.each do |config|
  config.build_settings.merge!(
    'PRODUCT_BUNDLE_IDENTIFIER' => 'com.example.pushLanguage',
    'INFOPLIST_KEY_CFBundleDisplayName' => 'Push Language Native',
    'INFOPLIST_KEY_UIApplicationSceneManifest_Generation' => 'YES',
    'INFOPLIST_KEY_UILaunchScreen_Generation' => 'YES',
    'INFOPLIST_KEY_UISupportedInterfaceOrientations' =>
      'UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight',
    'INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad' =>
      'UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight',
    'CURRENT_PROJECT_VERSION' => '1',
    'MARKETING_VERSION' => '0.1.0'
  )
end

unit_tests.add_dependency(app)
unit_tests.build_configurations.each do |config|
  config.build_settings['TEST_HOST'] = '$(BUILT_PRODUCTS_DIR)/PushLanguage.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/PushLanguage'
  config.build_settings['BUNDLE_LOADER'] = '$(TEST_HOST)'
end

ui_tests.add_dependency(app)
ui_tests.build_configurations.each do |config|
  config.build_settings['TEST_TARGET_NAME'] = 'PushLanguage'
end

project.save
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app)
scheme.set_launch_target(app)
scheme.add_test_target(unit_tests)
scheme.add_test_target(ui_tests)
scheme.save_as(project.path, 'PushLanguage', true)
puts "Generated #{project.path}"
