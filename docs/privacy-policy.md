# Privacy Policy — Badminton Score Tracker

*Last updated: July 11, 2026*

## Overview

Badminton Score Tracker is a watchOS app for tracking badminton match scores. Your privacy is important to us. This policy explains what data the app collects and how it is used.

## Data Collected

**Player names and match history** are stored locally on your device using Apple's UserDefaults (AppStorage). If you are signed into iCloud, this data is also synced across your devices using Apple's CloudKit private database (and shared zones for clubs you join). This data never leaves Apple's infrastructure and is not accessible to the developer.

**Workout data** — when you start a match, the app logs a badminton workout session to the Apple Health app using HealthKit. This data is stored in your personal Health database and is never transmitted to or accessed by the developer.

## Data Not Collected

- No personal information is collected
- No analytics or tracking
- No advertising
- No data is sent to any third-party server

## Third-Party Services

This app does not use any third-party SDKs, analytics tools, or advertising networks.

## iCloud

If you are signed into iCloud, match history, player roster, clubs, and settings are synced via CloudKit. Club data you share with other members uses CloudKit shared zones. Sync is handled entirely by Apple. You can disable iCloud for this app in **Settings → [your name] → iCloud** on your iPhone.

## HealthKit

The app requests permission to write workout data to Apple Health. This permission is optional — declining it does not affect scoring functionality. Health data is stored only in your personal Health database and is never shared with the developer.

## Contact

If you have questions about this privacy policy, please open an issue at [github.com/rinaba501/badminton-score-tracker](https://github.com/rinaba501/badminton-score-tracker).
