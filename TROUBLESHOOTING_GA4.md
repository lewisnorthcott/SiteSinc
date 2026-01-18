# Troubleshooting: GA4 Not Working on iOS

## The Problem

**GA4 Measurement Protocol requires an API Secret** to send events. Without it, events are rejected.

## ✅ Solution: Add API Secret (Required)

You **must** add an API secret for events to be stored in GA4.

### Step 1: Get Your API Secret

1. Go to [Google Analytics](https://analytics.google.com/)
2. Click **Admin** (bottom left)
3. Under **Property**, click **Data Streams**
4. Click on your stream (the one with `G-NB1WELHWYB`)
5. Scroll down to **Measurement Protocol API secrets**
6. Click **Create**
7. Give it a nickname: "iOS App"
8. Click **Create**
9. **Copy the secret immediately** (you can only see it once!)

### Step 2: Add to Info.plist

1. Open `SiteSinc/Info.plist` in Xcode
2. Find `GA_API_SECRET`
3. Paste your secret:

```xml
<key>GA_API_SECRET</key>
<string>your-secret-here</string>  <!-- Paste the secret you copied -->
```

### Step 3: Test

1. Build and run the app
2. Navigate to Drawings page
3. Check Xcode console - you should see:
   - `📊 [Analytics] Event: screen_view`
   - `✅ [Analytics] Event sent successfully: screen_view`
4. Check GA4 Real-Time Reports - events should appear within 10-30 seconds

## 🔍 Debugging Steps

### Check Console Logs

When you run the app, look for these messages in Xcode console:

**✅ Working:**
```
📊 [Analytics] Event: screen_view, Parameters: [...]
✅ [Analytics] Event sent successfully: screen_view
```

**❌ Not Working:**
```
⚠️ [Analytics] GA4 Measurement ID not configured
❌ [Analytics] Failed to send event: ...
⚠️ [Analytics] GA4 returned status: 400
```

### Check Network Requests

1. In Xcode, enable network logging:
   - Product → Scheme → Edit Scheme
   - Run → Arguments
   - Add: `-com.apple.CoreData.ConcurrencyDebug 1`
2. Or use a network proxy like Charles/Proxyman to see HTTP requests

### Verify Info.plist

Make sure both values are set:
```xml
<key>GA_MEASUREMENT_ID</key>
<string>G-NB1WELHWYB</string>  <!-- ✅ You have this -->

<key>GA_API_SECRET</key>
<string>your-secret-here</string>  <!-- ❌ This is empty - needs to be filled -->
```

## 🚨 Common Issues

### Issue 1: "GA4 returned status: 400"
**Cause:** Missing or invalid API secret
**Fix:** Add a valid API secret to Info.plist

### Issue 2: "GA4 returned status: 403"
**Cause:** Invalid API secret
**Fix:** Generate a new API secret and update Info.plist

### Issue 3: No console messages at all
**Cause:** Tracking code not being called
**Fix:** 
- Check that views have `.onAppear { AnalyticsManager.shared.trackScreenView(...) }`
- Verify the app is in DEBUG mode (messages only show in debug)

### Issue 4: Events appear in console but not in GA4
**Cause:** Using debug endpoint (no API secret)
**Fix:** Add API secret - debug endpoint validates but doesn't store data

## 📱 Testing Checklist

- [ ] API secret added to Info.plist
- [ ] Measurement ID is correct (`G-NB1WELHWYB`)
- [ ] App rebuilt after adding API secret
- [ ] Console shows `✅ Event sent successfully`
- [ ] Checked GA4 Real-Time Reports (wait 10-30 seconds)
- [ ] Network connection is active on device

## 🆘 Still Not Working?

1. **Check console logs** - Look for error messages
2. **Verify API secret** - Make sure it's correct in Info.plist
3. **Test with curl** (optional):
   ```bash
   curl -X POST "https://www.google-analytics.com/mp/collect?measurement_id=G-NB1WELHWYB&api_secret=YOUR_SECRET" \
     -H "Content-Type: application/json" \
     -d '{"client_id":"test-123","events":[{"name":"test_event","params":{}}]}'
   ```
4. **Check GA4 Real-Time** - Events can take 10-30 seconds to appear

## 💡 Alternative: Use Firebase Analytics

If you prefer, you can use Firebase Analytics instead (recommended for iOS):
- See `GOOGLE_ANALYTICS_SETUP.md` for Firebase setup
- Firebase handles the API secret automatically
