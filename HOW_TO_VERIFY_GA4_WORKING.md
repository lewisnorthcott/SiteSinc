# How to Verify GA4 is Working on iOS

## ✅ What Should Happen

After adding the API secret, events from your iOS app should appear in Google Analytics Real-Time reports within **10-30 seconds**.

## 🔍 Step-by-Step Verification

### 1. Check Xcode Console

When you run the app and navigate to screens, you should see:

```
📊 [Analytics] Event: screen_view, Parameters: [screen_name: Drawings, platform: ios, ...]
✅ [Analytics] Event sent successfully: screen_view
```

**If you see `✅ Event sent successfully`** → The event was sent to GA4!

**If you see `❌ Failed to send event`** → Check the error message

### 2. Check GA4 Real-Time Reports

1. Go to [Google Analytics](https://analytics.google.com/)
2. Select your property (the one with `G-NB1WELHWYB`)
3. Click **Reports** → **Real-time** (in left sidebar)
4. You should see:
   - **Users right now**: Should show 1 (you)
   - **Events by Event name**: Should show `screen_view` events
   - **Event count**: Should increase as you navigate

### 3. What Events to Look For

When you navigate in the app, you should see these events:

- **`screen_view`** - When you open any screen:
  - `screen_name: Login`
  - `screen_name: Project List`
  - `screen_name: Drawings`
  - `screen_name: Documents`
  - `screen_name: RFI List`
  - etc.

- **`project_view`** - When you open a project

- **`login`** - When you log in

- **`rfi_view`** - When you view an RFI

### 4. Test It Now

1. **Open the app** on your device/simulator
2. **Navigate to Drawings page**
3. **Wait 10-30 seconds**
4. **Check GA4 Real-Time Reports**
5. You should see `screen_view` events appearing!

## 📊 What You'll See in GA4

### Real-Time Overview
- **Users right now**: 1
- **Events in the last 30 minutes**: Increasing number
- **Top events**: `screen_view` should be at the top

### Event Details
Click on `screen_view` to see:
- **Event count**: Number of times it fired
- **Parameters**: 
  - `screen_name`: "Drawings", "Documents", etc.
  - `platform`: "ios"
  - `app_version`: Your app version
  - `project_id`: (if applicable)

## ⚠️ Troubleshooting

### Events Not Appearing?

1. **Wait longer**: GA4 can take 10-30 seconds to show events
2. **Check console**: Make sure you see `✅ Event sent successfully`
3. **Verify API secret**: Make sure it's correct in Info.plist
4. **Refresh GA4**: Refresh the Real-Time report page
5. **Check network**: Make sure device has internet connection

### Console Shows Errors?

- **`❌ Failed to send event`**: Check network connection
- **`⚠️ GA4 returned status: 400`**: API secret might be wrong
- **`⚠️ GA4 returned status: 403`**: API secret is invalid
- **`⚠️ GA4 Measurement ID not configured`**: Check Info.plist

## 🎯 Quick Test Checklist

- [ ] API secret added to Info.plist
- [ ] App rebuilt after adding API secret
- [ ] App running on device/simulator
- [ ] Navigated to Drawings page
- [ ] Console shows `✅ Event sent successfully`
- [ ] GA4 Real-Time report open
- [ ] Waited 10-30 seconds
- [ ] See `screen_view` events in GA4

## 💡 Pro Tip

Keep GA4 Real-Time report open in one browser tab while testing the app. You'll see events appear in real-time as you navigate!

## 📱 Testing Different Screens

Try navigating to different screens to see different events:

1. **Login** → `screen_view` with `screen_name: Login`
2. **Project List** → `screen_view` with `screen_name: Project List`
3. **Drawings** → `screen_view` with `screen_name: Drawings`
4. **Documents** → `screen_view` with `screen_name: Documents`
5. **RFI List** → `screen_view` with `screen_name: RFI List`

Each should appear in GA4 Real-Time within 10-30 seconds!
