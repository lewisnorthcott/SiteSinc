# Universal Links Setup Guide

This guide explains how to set up Universal Links so that email links open the SiteSinc app instead of the browser.

## What Are Universal Links?

Universal Links allow your app to respond to web URLs. When a user taps a link to your website, iOS checks if your app is installed. If it is, iOS opens your app instead of Safari. If not, iOS opens the link in Safari.

## Prerequisites

✅ **Already Configured:**
- Associated Domains entitlement is set up in `SiteSinc.entitlements`
- Domain: `applinks:www.sitesinc.co.uk`
- Deep link handling code is implemented in the app

## Server-Side Setup (Required)

You need to host an **Apple App Site Association (AASA)** file on your server. This file tells iOS which URLs your app can handle.

### 1. Create the AASA File

Create a file named `.well-known/apple-app-site-association` (no file extension) on your server at:

```
https://www.sitesinc.co.uk/.well-known/apple-app-site-association
```

### 2. AASA File Content

Here's the JSON structure you need (replace `TEAM_ID` and `BUNDLE_ID` with your actual values):

```json
{
  "applinks": {
    "apps": [],
    "details": [
      {
        "appID": "TEAM_ID.com.yourcompany.SiteSinc",
        "paths": [
          "/projects/*/drawings/*",
          "/projects/*/documents/*",
          "/projects/*/rfis/*",
          "/projects/*/rfi/*"
        ]
      }
    ]
  }
}
```

**Important Notes:**
- `TEAM_ID`: Your Apple Developer Team ID (found in Apple Developer account)
- `BUNDLE_ID`: Your app's bundle identifier (e.g., `com.yourcompany.SiteSinc`)
- `paths`: Array of URL paths your app can handle (supports wildcards)

### 3. Server Requirements

The AASA file must:
- ✅ Be served over HTTPS
- ✅ Be accessible without authentication
- ✅ Have `Content-Type: application/json` header
- ✅ Be no larger than 128 KB
- ✅ Be served with a valid SSL certificate

### 4. Verify AASA File

Test that your AASA file is accessible:
```bash
curl https://www.sitesinc.co.uk/.well-known/apple-app-site-association
```

You should see the JSON content returned.

### 5. Validate AASA File

Use Apple's validator:
- Visit: https://search.developer.apple.com/appsearch-validation-tool
- Enter your domain: `www.sitesinc.co.uk`
- Click "Validate"

## Email Link Format

When sending emails with links, use these formats:

### Drawing Links
```
https://www.sitesinc.co.uk/projects/{projectId}/drawings/{drawingId}
```

### Document Links
```
https://www.sitesinc.co.uk/projects/{projectId}/documents/{documentId}
```

### RFI Links
```
https://www.sitesinc.co.uk/projects/{projectId}/rfis/{rfiId}
```

### Alternative: Query Parameters
The app also supports query parameters:
```
https://www.sitesinc.co.uk/projects/{projectId}?drawingId={drawingId}
https://www.sitesinc.co.uk/projects/{projectId}?documentId={documentId}
https://www.sitesinc.co.uk/projects/{projectId}?rfiId={rfiId}
```

## Testing Universal Links

### 1. Test on Device (Not Simulator)

Universal Links work best on real devices. The simulator may not always handle them correctly.

### 2. Test Methods

**Method 1: Notes App**
1. Open Notes app on your iPhone
2. Type or paste a link: `https://www.sitesinc.co.uk/projects/1/drawings/1`
3. Long-press the link
4. You should see "Open in SiteSinc" option

**Method 2: Safari**
1. Open Safari
2. Type the URL in the address bar
3. If the app is installed, it should open the app
4. If not, it opens in Safari

**Method 3: Email**
1. Send yourself an email with a link
2. Tap the link
3. The app should open (if installed)

**Method 4: Messages**
1. Send yourself a message with a link
2. Tap the link
3. The app should open

### 3. Debug Universal Links

If links aren't working:

1. **Check AASA File:**
   ```bash
   curl -I https://www.sitesinc.co.uk/.well-known/apple-app-site-association
   ```
   Should return `Content-Type: application/json`

2. **Check Console Logs:**
   - Connect device to Xcode
   - Look for logs starting with `🔗` when tapping links

3. **Reset Universal Links Cache:**
   - Delete and reinstall the app
   - Or wait 24 hours for iOS to refresh the cache

4. **Verify Entitlements:**
   - Check `SiteSinc.entitlements` has `applinks:www.sitesinc.co.uk`

## How It Works

1. User receives email with link: `https://www.sitesinc.co.uk/projects/1/drawings/5`
2. User taps the link
3. iOS checks if app is installed
4. iOS checks AASA file on server
5. If path matches, iOS opens the app
6. App receives the URL via `onContinueUserActivity`
7. App parses the URL and navigates to the specific drawing

## Troubleshooting

### Links Open in Browser Instead of App

- ✅ Verify AASA file is accessible and valid
- ✅ Check that the URL path matches paths in AASA file
- ✅ Ensure app is installed and associated domains are configured
- ✅ Try deleting and reinstalling the app
- ✅ Wait 24 hours for iOS to refresh the association cache

### App Opens But Doesn't Navigate

- ✅ Check Xcode console for `🔗` logs
- ✅ Verify URL format matches expected patterns
- ✅ Ensure project/drawing/document IDs are valid
- ✅ Check that navigation listeners are set up correctly

### AASA File Not Found

- ✅ Verify file is at `/.well-known/apple-app-site-association`
- ✅ Check file has no extension
- ✅ Ensure HTTPS is working
- ✅ Verify Content-Type header is `application/json`

## Additional Resources

- [Apple Universal Links Documentation](https://developer.apple.com/documentation/xcode/supporting-universal-links-in-your-app)
- [Apple App Site Association Validator](https://search.developer.apple.com/appsearch-validation-tool)
- [Branch.io Universal Links Guide](https://branch.io/resources/aasa-validator/)

## Next Steps

1. ✅ App code is ready (already implemented)
2. ⏳ Create and host AASA file on server
3. ⏳ Test with real email links
4. ⏳ Update email templates to use correct URL format


