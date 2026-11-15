# Lumina

An experimental iOS personal-coaching and wellness-journal interface built with **SwiftUI** and **SwiftData**.

## Source components

- Goals, habits, journal entries, meals and workouts.
- Daily check-ins and progress-photo views.
- Persisted coach-memory models and an optional xAI chat client.
- HealthKit, notifications and Live Activity integration code.

## Current status

This is a personal software prototype. It seeds demonstration profile and activity data. Navigation, device integrations and live AI connectivity still require validation. The demo entries are illustrative.

Optional AI chat sends requests to xAI when configured.

## Development

Open `Lumina.xcodeproj` in Xcode. The shared scheme is `Lumina AI personal trainer`, targeting `Lumina`.

The project currently specifies Swift 5 language mode and an iOS 26.5 deployment target; use a compatible SDK. Live AI calls require your own `XAI_API_KEY` environment value and network access. No live service is needed to inspect the source.
