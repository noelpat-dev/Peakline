# Local Xcode configuration

`Peakline.xcconfig` contains nonpersonal defaults, including a neutral bundle
identifier, no development team, and the iOS 17 deployment baseline. It
optionally includes `Peakline.local.xcconfig` after those defaults.

For Noel's existing device installation, copy
`Peakline.local.xcconfig.example` to `Peakline.local.xcconfig` and set the
Apple development team and the bundle identifier used by that installation.
The local file is ignored by Git and applies to the app, unit-test, and UI-test
targets through the shared configuration variables.

HealthKit remains enabled in the project entitlements. A simulator build does
not require a personal team or private Firebase plist; physical-device
signing still requires a valid Apple team and provisioning setup.
