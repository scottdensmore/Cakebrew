#!/usr/bin/env ruby
# Adds the CakebrewUITests XCUITest target (and a shared scheme) to the Xcode
# project. Idempotent: re-running it is a no-op if the target already exists.
#
# Usage: ruby Tools/add-uitest-target.rb
# Requires the `xcodeproj` gem.

require "xcodeproj"

PROJECT_PATH = File.expand_path("../Cakebrew.xcodeproj", __dir__)
APP_TARGET_NAME = "Cakebrew"
UITEST_TARGET_NAME = "CakebrewUITests"

project = Xcodeproj::Project.open(PROJECT_PATH)
app_target = project.targets.find { |t| t.name == APP_TARGET_NAME }
raise "App target #{APP_TARGET_NAME} not found" unless app_target

if project.targets.any? { |t| t.name == UITEST_TARGET_NAME }
  puts "#{UITEST_TARGET_NAME} target already exists; nothing to do."
  exit 0
end

ui_target = project.new_target(:ui_test_bundle, UITEST_TARGET_NAME, :osx, "14.0", nil, :objc)

ui_target.build_configurations.each do |config|
  s = config.build_settings
  s["PRODUCT_BUNDLE_IDENTIFIER"] = "com.scottdensmore.CakebrewUITests"
  s["PRODUCT_NAME"] = "$(TARGET_NAME)"
  s["TEST_TARGET_NAME"] = APP_TARGET_NAME
  s["GENERATE_INFOPLIST_FILE"] = "YES"
  s["MACOSX_DEPLOYMENT_TARGET"] = "14.0"
  s["SDKROOT"] = "macosx"
  s["CODE_SIGN_STYLE"] = "Automatic"
  s["ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES"] = "NO"
  s["CLANG_ENABLE_OBJC_ARC"] = "YES"
end

# Build after the app so the app is available to launch.
ui_target.add_dependency(app_target)

# Source file group + reference.
group = project.main_group.find_subpath(UITEST_TARGET_NAME, true)
group.set_source_tree("SOURCE_ROOT")
group.set_path(UITEST_TARGET_NAME)
file_ref = group.new_reference("CakebrewUITests.m")
ui_target.add_file_references([file_ref])

project.save

# Shared scheme so `xcodebuild test -scheme CakebrewUITests` works in CI.
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app_target)
scheme.add_test_target(ui_target)
scheme.set_launch_target(app_target)
scheme.save_as(PROJECT_PATH, UITEST_TARGET_NAME, true)

puts "Added #{UITEST_TARGET_NAME} target and shared scheme."
