# FRC Attendance Tracker

## Install

### Supported Platforms
* Raspberry Pi (via Kiosk Installer)
* Android (Play Store or APK)
* iPadOS (App Store)
* Web (via GitHub Pages, older versions will remain accessible)

### Development Platforms

!!! warning
    These platforms will not receive any support, and are only intended for development purposes.

[GitHub Releases](https://github.com/meowmeowahr/attendance_tracker_prototype_flutter/releases)

* Windows x86_64
* Linux x86_64 and ARM64
* macOS x86_64 and ARM64

## Configure

wip

## Contribute

wip

## Introduction

Attendance tracker is an app to track the attendance of students, mentors, coaches and volunteers to/from events for the purpose of being able to note hours given to our local community.

This tracker does NOT track any precise location data other than a generic tag such as “Workshop”, “RoughRiders 2025”, “Library June 2025” etc...

Data collected is stored remotely in a Google Sheet. 
The app will periodically sync with the sheet to update the member list, locations, and status. 
If the connection is lost or unavailable, the app will keep a running list of events to push to the sheet when the connection is restored.

## Features

* Support 300+ members
* Support multiple simultaneous kiosks to allow multiple entry points to the facility.
* Be as quick and easy as possible to sign in/out
* Somewhat "fun" to interact with
* Support RFID tags for quick processing
* Support easy data processing for reports etc...
* Provide basic administration features
* Able to operate without additional accounts/servers/fees etc… (depending on features needed)
* Cross-platform support for Linux (x86 and ARM), macOS (x86 and ARM), Windows (x86 ONLY), Android, iPadOS, and Web
* Open source, expandable and available for anyone to implement
* Support off site events (remote, portable device that can sync in real time with a hotspot or at a later time)
* Allow for team branding with team logo and accent color

### Non-Features

The attendance tracker is not meant to be a fully featured, all singing, all dancing access tracker. Other options available seem to cost many $100s (even $1000s!!) and/or require provider accounts, server costs etc... It is not massively complex, does not inherently provide any data analysis.

## Limitations

### Google Sheets interface

#### Workbooks

* 10 million cells
* 18,278 columns
* 200 sheets
* Update 40,000 rows at once

#### Data transfer

##### Read requests

* 300 per minute per project
* 60 per minute per user per project

!!! Info
    This is effectively the limit for the attendance tracker unless each station is configured as a different user

##### Write requests

* 300 per minute per project
* 60 per minute per user per project (This is effectively the limit for attendance tracker unless each station is configured as a different user)