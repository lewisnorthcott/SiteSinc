# Debugging: Firebase Analytics Not Showing in GA4

## The Problem

Firebase Analytics events are being sent, but not appearing in Google Analytics Real-Time reports.

## Most Likely Cause

Firebase Analytics is sending to a **different GA4 property** than your website, OR Firebase isn't properly linked to Google Analytics.

## Step-by-Step Debugging

### Step 1: Check Which GA4 Property Firebase is Linked To

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your **SiteSinc** project
3. Click **gear icon** → **Project settings**
4. Click **Integrations** tab
5. Look at **Google Analytics** section
6. Check which property it says: 
   - Should be: **SiteSinc.com (513327045)**
   - Currently might be: **sitesinc-c7f1d (520435685)**

### Step 2: Check Firebase Analytics DebugView

1. In Xcode: **Product → Scheme → Edit Scheme**
2. **Run** → **Arguments** tab
3. Add launch argument: `-FIRAnalyticsDebugEnabled`
4. Run the app
5. Go to **Firebase Console → Analytics → DebugView**
6. Navigate in your app - do you see events here?

**If events appear in DebugView but not GA4:**
→ Firebase is working, but not linked to the right GA4 property

**If events DON'T appear in DebugView:**
→ Firebase Analytics isn't working at all (check console logs)

### Step 3: Link Firebase to Your Website's GA4 Property

If Firebase is linked to the wrong property:

1. In Firebase Console → Project settings → Integrations
2. Click **three dots (⋮)** next to Google Analytics
3. Click **Unlink**
4. Click **Link Google Analytics** again
5. Select **SiteSinc.com (513327045)** - your website's property
6. Click **Link**

### Step 4: Check Console Logs

When you run the app, check Xcode console for:

**✅ Good signs:**
```
🔥 [Firebase] Firebase configured successfully
📊 [Analytics] Event: screen_view
✅ [Analytics] Event sent via Firebase: screen_view
```

**❌ Bad signs:**
```
❌ [Firebase] Error: ...
⚠️ [Analytics] ...
```

### Step 5: Verify You're Looking at the Right GA4 Property

In Google Analytics:
1. Check the property selector (top left)
2. Make sure you're viewing **SiteSinc.com (513327045)**
3. NOT **sitesinc-c7f1d (520435685)**

### Step 6: Wait for Data

- Firebase Analytics → GA4 can take **5-30 minutes** for first events
- Real-Time reports show events within **10-30 seconds** after linking
- If you just linked, wait a few minutes

## Quick Test

1. Enable debug mode in Xcode (add `-FIRAnalyticsDebugEnabled`)
2. Run app
3. Navigate to Drawings page
4. Check **Firebase Console → Analytics → DebugView**
5. If events appear there → Firebase is working, just need to link to right GA4 property
6. If events DON'T appear → Check console logs for errors

## Common Issues

### Issue 1: Wrong GA4 Property
**Symptom:** Events in Firebase but not in GA4 Real-Time
**Fix:** Link Firebase to your website's GA4 property (SiteSinc.com)

### Issue 2: Not Linked at All
**Symptom:** Firebase Analytics shows data, but GA4 doesn't
**Fix:** Go to Firebase → Project settings → Integrations → Link Google Analytics

### Issue 3: Analytics Disabled
**Symptom:** No events anywhere
**Fix:** Check `IS_ANALYTICS_ENABLED` in GoogleService-Info.plist (should be `true`)

### Issue 4: Wrong Project
**Symptom:** Looking at wrong GA4 property
**Fix:** Make sure you're viewing **SiteSinc.com** property in GA4, not sitesinc-c7f1d
