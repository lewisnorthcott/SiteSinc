# Google Analytics 4 (GA4) Setup for iOS

This document describes how to complete the Firebase/GA4 integration for the SiteSinc iOS app.

## Overview

The analytics tracking code has been implemented in `AnalyticsManager.swift`. The implementation mirrors the frontend web analytics (`analytics.ts`) for consistency across platforms.

## Current Implementation Status

✅ **Completed:**
- `AnalyticsManager.swift` - Core analytics manager with all tracking methods
- Screen view tracking via `.trackScreen()` view modifier
- Event tracking for all major features
- User ID and tenant ID tracking
- Integration points in key views

### Screens Being Tracked:
- Login
- Project List
- Project Summary (with project view event)
- RFI List & Detail
- Drawings
- Documents
- Forms
- Photos
- Inspections
- Logs (Daily Diary)
- Material Requisitions

### Events Being Tracked:
- `login` / `logout`
- `project_view`
- `rfi_create` / `rfi_view` / `rfi_response` / `rfi_status_change`
- `drawing_upload` / `drawing_view` / `drawing_download`
- `document_upload` / `document_view` / `document_download`
- `form_submission` / `form_create`
- `photo_upload` / `photo_view`
- `daily_diary_create` / `daily_diary_view`
- `material_requisition_create` / `material_requisition_status_change`
- `inspection_create` / `inspection_complete` / `inspection_view`
- `snag_create` / `snag_view` / `snag_status_change`
- `feature_search` / `feature_filter` / `export`

## Setup Instructions

### Step 1: Create Firebase Project (if not already done)

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Create a new project or use your existing SiteSinc project
3. Enable Google Analytics for the project

### Step 2: Add iOS App to Firebase

1. In Firebase Console, click "Add app" → iOS
2. Enter your iOS bundle ID: `com.sitesinc.SiteSinc` (or your actual bundle ID)
3. Download `GoogleService-Info.plist`
4. Add the file to your Xcode project (drag into SiteSinc folder, ensure "Copy items if needed" is checked)

### Step 3: Add Firebase SDK via Swift Package Manager

1. In Xcode: **File → Add Package Dependencies**
2. Enter URL: `https://github.com/firebase/firebase-ios-sdk`
3. Select version (recommend latest stable)
4. Choose products to add:
   - `FirebaseAnalytics` (required)
   - `FirebaseCore` (required)

### Step 4: Initialize Firebase

In `SiteSincApp.swift`, uncomment the Firebase initialization:

```swift
import FirebaseCore
import FirebaseAnalytics

@main
struct SiteSincApp: App {
    init() {
        print("🚀 [App] SiteSincApp initializing...")
        
        // Initialize Firebase
        FirebaseApp.configure()
        
        #if DEBUG
        AnalyticsManager.shared.debugMode = true
        #endif
    }
    // ...
}
```

### Step 5: Enable Firebase Analytics Calls

In `AnalyticsManager.swift`, uncomment the Firebase Analytics calls:

```swift
// In trackEvent method:
Analytics.logEvent(eventName, parameters: params)

// In trackScreenView method:
Analytics.setScreenName(screenName, screenClass: screenClass)

// In setUserId method:
Analytics.setUserID(String(userId))

// In setUserProperty method:
Analytics.setUserProperty(value, forName: name)
```

### Step 6: Link GA4 to Firebase

1. In Firebase Console → Analytics → Settings
2. Link to your Google Analytics 4 property
3. Or create a new GA4 property if needed

## Testing

### Debug Mode

The app runs in debug mode by default in DEBUG builds, which logs all analytics events to the console:

```
📊 [Analytics] Event: screen_view, Parameters: [screen_name: Project List, platform: ios, ...]
```

### Firebase DebugView

To see events in real-time in Firebase Console:

1. In Xcode, edit scheme → Run → Arguments
2. Add launch argument: `-FIRAnalyticsDebugEnabled`
3. Run the app
4. In Firebase Console → Analytics → DebugView

### GA4 Real-Time Reports

After linking Firebase to GA4:
1. Go to GA4 → Reports → Real-time
2. Events should appear within seconds

## Event Naming Convention

All events follow GA4 recommended naming conventions:
- Snake_case format
- Maximum 40 characters
- No spaces or special characters

## Custom Dimensions

The following custom dimensions are tracked:
- `platform`: Always "ios" for mobile app
- `app_version`: Current app version
- `project_id`: Associated project ID (where applicable)
- `tenant_id`: User's tenant ID (set as user property)

## Privacy Considerations

- No PII (Personally Identifiable Information) is tracked
- User IDs are numeric internal IDs, not email addresses
- All tracking respects user consent (implement consent management if required)

## Troubleshooting

### Events Not Appearing

1. Ensure `GoogleService-Info.plist` is in the correct location
2. Verify Firebase is initialized before any analytics calls
3. Check console for any Firebase errors
4. Use DebugView to verify events are being sent

### Missing User Properties

User properties may take up to 24 hours to appear in GA4 reports.

### Build Errors

If you get build errors after adding Firebase:
1. Clean build folder (Cmd+Shift+K)
2. Reset package caches (File → Packages → Reset Package Caches)
3. Ensure minimum iOS deployment target is compatible with Firebase SDK

## Adding New Tracking

To add tracking to a new view:

```swift
// Simple screen tracking
.onAppear {
    AnalyticsManager.shared.trackScreenView("My New Screen", projectId: projectId)
}

// Or use the view modifier
.trackScreen("My New Screen", projectId: projectId)
```

To track a custom event:

```swift
AnalyticsManager.shared.trackEvent("my_custom_event", parameters: [
    "custom_param": "value",
    "project_id": String(projectId)
])
```

## Related Files

- `/SiteSinc/Managers/AnalyticsManager.swift` - Core analytics implementation
- `/SiteSinc/SiteSincApp.swift` - Firebase initialization
- `/SiteSinc/SessionManager.swift` - Login/logout tracking
- Frontend equivalent: `/apps/frontend/src/lib/analytics.ts`
