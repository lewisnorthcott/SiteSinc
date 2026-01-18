# GA4 Setup Quick Start for iOS

## ✅ Implementation Complete

The analytics tracking code is now implemented and will send events directly to Google Analytics using the GA4 Measurement Protocol.

## 🚀 Quick Setup (2 Steps)

### Step 1: Get Your GA4 Measurement ID

1. Go to [Google Analytics](https://analytics.google.com/)
2. Select your property (or create one)
3. Go to **Admin** → **Data Streams**
4. Click on your iOS app stream (or create one)
5. Copy the **Measurement ID** (format: `G-XXXXXXXXXX`)

### Step 2: Add to Info.plist

1. Open `SiteSinc/Info.plist` in Xcode
2. Find the `GA_MEASUREMENT_ID` key (already added)
3. Replace `G-XXXXXXXXXX` with your actual Measurement ID

```xml
<key>GA_MEASUREMENT_ID</key>
<string>G-XXXXXXXXXX</string>  <!-- Replace with your ID -->
```

### Optional: Add API Secret (Recommended for Production)

For better security, add an API secret:

1. In GA4 → Admin → Data Streams → Your Stream → **Measurement Protocol API secrets**
2. Click **Create** to generate a secret
3. Copy the secret
4. Add to `Info.plist`:

```xml
<key>GA_API_SECRET</key>
<string>your-api-secret-here</string>
```

## ✅ That's It!

Events will now be sent to Google Analytics automatically. You can verify in:

- **GA4 Real-Time Reports**: Events appear within seconds
- **Console Logs**: In debug mode, you'll see `📊 [Analytics] Event:` messages

## 📊 What's Being Tracked

All major screens and events are already tracked:
- Screen views (Drawings, Documents, RFI, Forms, Photos, etc.)
- User actions (login, logout, project views)
- Feature interactions (RFI creation, drawing views, etc.)

## 🔍 Testing

1. Run the app
2. Navigate to the Drawings page
3. Check GA4 Real-Time Reports → Events
4. You should see `screen_view` events with `screen_name: Drawings`

## 🐛 Troubleshooting

### Events Not Appearing

1. **Check Measurement ID**: Ensure it's correct in Info.plist (format: `G-XXXXXXXXXX`)
2. **Check Console**: Look for `📊 [Analytics]` messages - if you see warnings, the ID might be wrong
3. **Wait a few seconds**: GA4 Real-Time can take 10-30 seconds to show events
4. **Check Network**: Ensure device has internet connection

### Still Not Working?

Check the console for:
- `⚠️ [Analytics] GA4 Measurement ID not configured` → Add to Info.plist
- `❌ [Analytics] Failed to send event` → Check network connection
- No messages at all → Check that tracking code is being called

## 📝 Notes

- Events are sent asynchronously (won't block the app)
- Client ID is automatically generated and stored per device
- User ID is set after login
- All events include `platform: ios` and `app_version` parameters
