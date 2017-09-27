
plugin 'cocoapods-keys', {
  :keys => [
    "GitHubAPIClientId",
    "GitHubAPIClientSecret",
    "BitBucketAPIClientId",
    "BitBucketAPIClientSecret"
]}

source 'https://github.com/CocoaPods/Specs.git'
source 'https://github.com/s-faychatelard/Buildasaur-podspecs.git'

project 'Buildasaur', 'Testing' => :debug

platform :osx, '10.11'
use_frameworks!
inhibit_all_warnings!

def pods_for_errbody
    pod 'BuildaUtils', '~> 0.4.1'
end

def rac
    pod 'ReactiveCocoa', '~> 6.0.1'
end

def also_xcode_pods
    pods_for_errbody
    pod 'XcodeServerSDK', '~> 0.7.3'
    pod 'ekgclient', '~> 0.3.3'
end

def buildasaur_app_pods
    also_xcode_pods
    rac
    pod 'Ji', '~> 2.0.1'
    pod 'CryptoSwift', '~> 0.7.2'
    pod 'Sparkle'
    pod 'KeychainAccess', '~> 3.1.0'
end

def test_pods
    pod 'Nimble', '~> 7.0.2'
    pod 'DVR', '~> 1.1.0'
end

target 'Buildasaur' do
    buildasaur_app_pods
    pod 'Crashlytics'
    pod 'OAuthSwift'
end

target 'BuildaKit' do
    buildasaur_app_pods
end

target 'BuildaKitTests' do
    buildasaur_app_pods
    test_pods
end

target 'BuildaGitServer' do
    pods_for_errbody
    rac
end

target 'BuildaGitServerTests' do
    pods_for_errbody
    rac
    test_pods
end

target 'BuildaHeartbeatKit' do
    also_xcode_pods
end



