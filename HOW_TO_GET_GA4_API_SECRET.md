# How to Get GA4 API Secret (Optional)

The API Secret is **optional** - your analytics will work without it, but it's **recommended for production** for better security.

## Is It Required?

**No, it's optional.** The app will work fine without it. However, adding it provides:
- ✅ Better security (prevents unauthorized data sending)
- ✅ Higher rate limits
- ✅ Better data validation

## Where to Find It

1. Go to [Google Analytics](https://analytics.google.com/)
2. Click **Admin** (gear icon, bottom left)
3. Under **Property**, click **Data Streams**
4. Click on your **Web stream** (or iOS stream if you created one)
5. Scroll down to find **Measurement Protocol API secrets**
6. Click **Create** (or use existing if you have one)
7. Give it a nickname (e.g., "iOS App")
8. Click **Create**
9. **Copy the secret** - it will look like: `AbCdEfGhIjKlMnOpQrStUvWxYz123456`

⚠️ **Important**: Copy it immediately - you can only see it once!

## How to Add It

1. Open `SiteSinc/Info.plist` in Xcode
2. Find the `GA_API_SECRET` key (already added)
3. Paste your secret:

```xml
<key>GA_API_SECRET</key>
<string>AbCdEfGhIjKlMnOpQrStUvWxYz123456</string>  <!-- Your secret here -->
```

## If You Don't Want to Use It

That's fine! Just leave it empty in Info.plist:

```xml
<key>GA_API_SECRET</key>
<string></string>  <!-- Empty is OK -->
```

The app will use the public endpoint without the API secret. This works perfectly fine for most use cases.

## Quick Setup Priority

1. **First**: Add `GA_MEASUREMENT_ID` (required)
2. **Then**: Add `GA_API_SECRET` (optional, but recommended)

Your analytics will work with just the Measurement ID!
