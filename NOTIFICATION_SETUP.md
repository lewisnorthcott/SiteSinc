# Notification System Setup Guide

This guide explains how to set up push notifications for drawing uploads in your SiteSinc iOS app.

## Overview

The notification system consists of:
1. **iOS App**: Handles device token registration, notification preferences, and local notifications
2. **Backend API**: Manages device tokens, notification preferences, and sends push notifications
3. **Database**: Stores user notification preferences and device tokens

## iOS App Setup

### 1. Files Added/Modified

#### New Files:
- `NotificationManager.swift` - Core notification handling
- `NotificationSettingsView.swift` - UI for managing notification preferences

#### Modified Files:
- `SiteSincApp.swift` - Integrated NotificationManager and AppDelegate
- `APIClient.swift` - Added device token registration endpoint
- `ProjectSummaryView.swift` - Added notification settings button

### 2. Key Features

#### NotificationManager Features:
- ✅ Request notification permissions
- ✅ Register device token with backend
- ✅ Fetch/update notification preferences
- ✅ Schedule local notifications
- ✅ Handle notification actions (View Drawing, View Project)
- ✅ Show notifications when app is in foreground

#### NotificationSettingsView Features:
- ✅ Drawing upload preferences (Instant/Daily/Weekly/None)
- ✅ Document upload preferences
- ✅ RFI notification toggles
- ✅ Permission status display
- ✅ Save preferences to backend

### 3. Testing

The app includes a test notification button in the Project Summary view (only visible when notifications are authorized). This allows you to test the notification system without actually uploading drawings.

## Backend Setup

### 1. Required Backend Endpoints

Your backend needs these endpoints:

#### Device Token Registration
```
POST /api/notifications/register-device
Authorization: Bearer <token>
Content-Type: application/json

{
  "deviceToken": "string",
  "platform": "ios"
}
```

#### Notification Preferences
```
GET /api/notifications/preferences?projectId=<id>
Authorization: Bearer <token>

PUT /api/notifications/preferences
Authorization: Bearer <token>
Content-Type: application/json

{
  "projectId": 123,
  "drawingUpdatesPreference": "instant",
  "documentUpdatesPreference": "instant",
  "rfiNotifications": {
    "enabled": true
  }
}
```

### 2. Database Schema

You already have the `NotificationPreference` table in your schema:

```sql
model NotificationPreference {
  id                        Int      @id @default(autoincrement())
  userId                    Int
  projectId                 Int
  tenantId                  Int
  drawingUpdatesPreference  String   @default("none")
  documentUpdatesPreference String   @default("none")
  rfiNotifications          Json?
  createdAt                 DateTime @default(now())
  updatedAt                 DateTime @updatedAt

  user    User    @relation(fields: [userId], references: [id])
  project Project @relation(fields: [projectId], references: [id])
  tenant  Tenant  @relation(fields: [tenantId], references: [id])

  @@unique([userId, projectId, tenantId])
}
```

### 3. Backend Implementation

You need to implement these backend features:

#### A. Device Token Storage
Create a table to store device tokens:
```sql
model DeviceToken {
  id        Int      @id @default(autoincrement())
  userId    Int
  token     String   @unique
  platform  String
  createdAt DateTime @default(now())
  updatedAt DateTime @updatedAt

  user User @relation(fields: [userId], references: [id])
}
```

#### B. Push Notification Service
Implement a service to send push notifications:

```typescript
// notificationService.ts
export const sendDrawingUploadNotification = async (
  userId: number,
  drawingTitle: string,
  projectName: string,
  drawingNumber: string
) => {
  // 1. Get user's device tokens
  const deviceTokens = await prisma.deviceToken.findMany({
    where: { userId }
  });

  // 2. Get user's notification preferences
  const preferences = await prisma.notificationPreference.findMany({
    where: { userId }
  });

  // 3. Check if user wants instant notifications
  const wantsInstant = preferences.some(p => 
    p.drawingUpdatesPreference === 'instant'
  );

  if (wantsInstant && deviceTokens.length > 0) {
    // 4. Send push notification
    await sendPushNotification({
      tokens: deviceTokens.map(dt => dt.token),
      title: "New Drawing Uploaded",
      body: `Drawing ${drawingNumber}: ${drawingTitle} has been uploaded to ${projectName}`,
      data: {
        type: "drawing_upload",
        drawingTitle,
        projectName,
        drawingNumber
      }
    });
  }
};
```

#### C. Drawing Upload Trigger
Modify your drawing upload endpoint to trigger notifications:

```typescript
// In your drawing upload endpoint
export const uploadDrawing = async (req, res) => {
  // ... existing upload logic ...

  // After successful upload, send notifications
  const project = await prisma.project.findUnique({
    where: { id: projectId },
    include: { assignedUsers: true }
  });

  // Send notifications to all assigned users
  for (const user of project.assignedUsers) {
    await sendDrawingUploadNotification(
      user.id,
      drawing.title,
      project.name,
      drawing.number
    );
  }

  res.json({ success: true });
};
```

## Push Notification Service Setup

### 1. Apple Push Notification Service (APNs)

You'll need to set up APNs for production:

1. **Create APNs Certificate** in Apple Developer Console
2. **Upload certificate** to your backend
3. **Use a library** like `node-apn` or `apn` for Node.js

### 2. Firebase Cloud Messaging (FCM) - Alternative

For cross-platform support, consider using FCM:

```typescript
import * as admin from 'firebase-admin';

// Initialize Firebase Admin
admin.initializeApp({
  credential: admin.credential.applicationDefault(),
  projectId: 'your-project-id'
});

export const sendPushNotification = async ({
  tokens,
  title,
  body,
  data
}) => {
  const message = {
    notification: {
      title,
      body
    },
    data,
    tokens
  };

  try {
    const response = await admin.messaging().sendMulticast(message);
    console.log('Successfully sent messages:', response.successCount);
  } catch (error) {
    console.error('Error sending messages:', error);
  }
};
```

## Testing the System

### 1. iOS App Testing

1. **Build and run** the iOS app
2. **Grant notification permissions** when prompted
3. **Navigate to Project Summary** and tap the notification bell icon
4. **Configure notification preferences**
5. **Test notifications** using the "Test Notification" button

### 2. Backend Testing

1. **Test device token registration**:
   ```bash
   curl -X POST http://localhost:3000/api/notifications/register-device \
     -H "Authorization: Bearer <token>" \
     -H "Content-Type: application/json" \
     -d '{"deviceToken": "test-token", "platform": "ios"}'
   ```

2. **Test notification preferences**:
   ```bash
   curl -X GET "http://localhost:3000/api/notifications/preferences?projectId=1" \
     -H "Authorization: Bearer <token>"
   ```

## Production Considerations

### 1. Security
- ✅ Validate device tokens
- ✅ Rate limit notification sending
- ✅ Sanitize notification content
- ✅ Implement proper error handling

### 2. Performance
- ✅ Batch notifications for daily/weekly summaries
- ✅ Use background jobs for notification sending
- ✅ Implement retry logic for failed notifications

### 3. User Experience
- ✅ Allow users to disable notifications per project
- ✅ Provide clear notification content
- ✅ Handle notification actions properly
- ✅ Show notification status in UI

## Troubleshooting

### Common Issues:

1. **Notifications not showing**: Check notification permissions in iOS Settings
2. **Device token not registering**: Verify backend endpoint is working
3. **Preferences not saving**: Check API response and error handling
4. **Test notifications not working**: Ensure NotificationManager is properly initialized

### Debug Steps:

1. Check console logs for notification-related messages
2. Verify device token is being sent to backend
3. Test backend endpoints independently
4. Check notification preferences in iOS Settings

## Next Steps

1. **Implement backend endpoints** for device token registration and preferences
2. **Set up push notification service** (APNs or FCM)
3. **Add notification triggers** to drawing upload endpoints
4. **Test the complete flow** from drawing upload to notification delivery
5. **Add more notification types** (RFI updates, document uploads, etc.)
6. **Implement notification analytics** to track engagement

The iOS app is now ready to receive and handle notifications. The backend implementation will complete the system and enable real-time notifications when drawings are uploaded. 