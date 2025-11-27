# RFI Notification System Review

## Overview

This document reviews how RFI notification emails are issued and the current state of RFI reminder functionality.

## RFI Notification Emails

### How They Are Issued

RFI notification emails are **sent by the backend server**, not by the iOS app. The iOS app receives real-time updates via Server-Sent Events (SSE) but does not send emails directly.

### When RFI Emails Are Sent

Based on the codebase analysis, RFI notification emails are likely sent by the backend in the following scenarios:

1. **RFI Created** (`POST /api/rfis`)
   - When a new RFI is created via `CreateRFIView.swift`
   - Email sent to:
     - RFI Manager (managerId)
     - Assigned Users (assignedUserIds)
     - Project stakeholders

2. **RFI Updated** (`PATCH /api/projects/{projectId}/rfis/{rfiId}`)
   - When RFI details are modified
   - Status changes
   - Return date changes

3. **RFI Response Added** (`POST /api/projects/{projectId}/rfis/{rfiId}/responses`)
   - When a response is submitted to an RFI
   - Email sent to RFI creator and manager

4. **RFI Response Accepted** (`PATCH /api/projects/{projectId}/rfis/{rfiId}/responses/{responseId}`)
   - When a response is accepted
   - Email sent to response submitter

5. **RFI Response Rejected** (`POST /api/rfis/{rfiId}/responses/reject`)
   - When a response is rejected
   - Email sent to response submitter with rejection reason

6. **RFI Closed** (`PATCH /api/projects/{projectId}/rfis/{rfiId}` with status="closed")
   - When RFI is marked as closed
   - Email sent to all stakeholders

7. **RFI Reopened** (`PATCH /api/projects/{projectId}/rfis/{rfiId}` with status="open")
   - When a closed RFI is reopened
   - Email sent to all stakeholders

### iOS App Real-Time Updates

The iOS app receives real-time RFI events via Server-Sent Events (SSE) through:

- **RFIEventManager** (`SiteSinc/RFI/RFIEventManager.swift`)
  - Connects to `/api/rfis/events?projectId={id}&token={token}`
  - Handles events: `created`, `updated`, `deleted`, `response_added`, `response_accepted`, `response_rejected`, `closed`, `reopened`
  - Posts local notifications via `NotificationCenter` for UI updates

### Push Notifications

The app can receive push notifications for RFI updates:

- **NotificationManager** handles RFI push notifications
- User preferences can be set in **NotificationSettingsView** with granular controls:
  - **All RFI Activity** (instant/daily/none) - Receive notifications for any RFI activity
  - **Notify on Creation** (instant/daily/none) - When a new RFI is created
  - **Notify on Response** (instant/daily/none) - When an RFI receives a response
  - **Notify on Status Change** (instant/daily/none) - When RFI status changes (accepted/rejected)
  - **Notify on Reminder** (daily/none) - Daily reminders for RFIs approaching or past due date
- Preferences are per-project and match the web app structure
- Push notifications include deep linking to specific RFIs

### Backend Email Implementation (Not in iOS Codebase)

The actual email sending happens on the backend. You should verify your backend implementation includes:

1. **Email Service**: SMTP/email service integration (SendGrid, AWS SES, etc.)
2. **Email Templates**: HTML/text templates for each RFI event type
3. **Email Triggers**: Hooks in RFI creation/update/response endpoints
4. **Recipient Logic**: Determining who receives emails based on:
   - RFI manager
   - Assigned users
   - Project permissions
   - User notification preferences

## RFI Morning Reminders

### Current Status

✅ **IMPLEMENTED** - Daily morning reminders are now implemented in the iOS app using local notifications.

### Implementation Details

#### iOS Notification Preferences (Aligned with Web App)

The iOS app now matches the web app's granular RFI notification structure:

1. **RFI Notification Options** (`NotificationSettingsView.swift`)
   - **All RFI Activity** - Control all RFI notifications at once (instant/daily/none)
   - **Notify on Creation** - When new RFIs are created (instant/daily/none)
   - **Notify on Response** - When RFIs receive responses (instant/daily/none)
   - **Notify on Status Change** - When RFI status changes (instant/daily/none)
   - **Notify on Reminder** - Daily reminders for pending RFIs (daily/none)
   - All preferences are per-project and saved to backend

2. **API Integration** (`NotificationManager.swift`)
   - Uses `/api/notifications/preferences` for fetching all preferences
   - Uses `/api/notifications/preferences/rfi` for RFI-specific updates
   - Matches backend structure with `projectSpecificPreferences` array
   - Handles both old and new preference formats for backward compatibility

3. **Daily Reminder Scheduling** (`NotificationManager.swift`)
   - Uses `UNCalendarNotificationTrigger` for daily repeats
   - Default time: 8:00 AM
   - Automatically enabled when `notifyOnReminder` is set to "daily"
   - Reminders persist across app restarts

4. **Key Methods:**
   - `fetchNotificationPreferences(projectId:)` - Fetches all user preferences
   - `updateNotificationPreferences(projectId:preferences:)` - Updates preferences (uses RFI endpoint when appropriate)
   - `scheduleDailyRFIReminder(hour:minute:)` - Schedules daily reminder
   - `cancelDailyRFIReminder()` - Cancels reminder
   - `updateRFIReminderSchedule(enabled:hour:minute:)` - Updates schedule
   - `restoreRFIReminderFromPreferences()` - Restores on app launch
   - `checkRFIReminderStatus()` - Checks if reminder is scheduled

5. **Integration:**
   - Preferences are automatically loaded when settings view appears
   - Settings are saved to backend when user updates preferences
   - Reminders are automatically restored when app launches
   - Works with notification permission system

### Recommended Backend Implementation

**For Email Reminders (Still Recommended):**

A backend cron job or scheduled task should also be implemented:
- Runs daily at a specified morning time (e.g., 8:00 AM)
- Queries all open RFIs with approaching return dates
- Sends reminder emails to assigned users and managers
- Respects user notification preferences
- Can include detailed RFI information in email

**Advantages of Backend Email Reminders:**
- Works even if app is not installed
- Can batch multiple RFIs in one email
- More detailed information can be included
- Works across all devices/platforms

### Hybrid Approach (Current + Recommended)

1. ✅ **iOS Local Notifications** - Implemented for in-app reminders
2. ⚠️ **Backend Email Reminders** - Should be implemented for comprehensive coverage
3. ✅ **User Preferences** - Control both notification types

## Next Steps

1. ✅ Review backend RFI email implementation
2. ✅ Verify email templates and recipient logic
3. ⚠️ Implement backend daily reminder cron job
4. ⚠️ Add iOS local notification reminder option (optional)
5. ⚠️ Add user preference for reminder time

## Files Related to RFI Notifications

### iOS App Files:
- `SiteSinc/RFI/RFIEventManager.swift` - SSE event handling
- `SiteSinc/RFI/CreateRFIView.swift` - RFI creation (triggers backend email)
- `SiteSinc/NotificationManager.swift` - Push notification handling
- `SiteSinc/NotificationSettingsView.swift` - User preferences
- `SiteSinc/APIClient.swift` - RFI API endpoints
- `SiteSinc/RFI/RFIsListView.swift` - RFI list with real-time updates

### Backend Endpoints (Referenced):
- `POST /api/rfis` - Create RFI
- `GET /api/rfis?projectId={id}` - Fetch RFIs
- `GET /api/rfis/events` - SSE endpoint
- `PATCH /api/projects/{projectId}/rfis/{rfiId}` - Update RFI
- `POST /api/projects/{projectId}/rfis/{rfiId}/responses` - Add response
- `PATCH /api/projects/{projectId}/rfis/{rfiId}/responses/{responseId}` - Review response

