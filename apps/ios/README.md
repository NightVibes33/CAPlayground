# CAPlayground for iOS

This directory contains the native iPhone and iPad application. It uses SwiftUI
for the application shell and inspectors, UIKit for editor interaction, and
QuartzCore for rendering. It does not embed the web application.

## Build

Open `CAPlayground.xcodeproj`, select the shared `CAPlayground` scheme, and run
on iOS 26 or later. The unsigned device artifact is built by
`.github/workflows/ios-unsigned.yml`.

The bundle identifier is `com.nightvibes33.caplayground`.
