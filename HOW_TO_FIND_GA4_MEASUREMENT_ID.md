# How to Find Your GA4 Measurement ID

Since you're using Google Tag Manager on your website, you can use the **same GA4 property** for your iOS app. Here's how to find your GA4 Measurement ID:

## Method 1: From Google Analytics (Easiest)

1. Go to [Google Analytics](https://analytics.google.com/)
2. Select your **SiteSinc property** (the same one your website uses)
3. Click **Admin** (gear icon, bottom left)
4. Under **Property**, click **Data Streams**
5. You'll see your data streams listed
6. Click on your **Web stream** (or iOS stream if you have one)
7. Your **Measurement ID** is displayed at the top (format: `G-XXXXXXXXXX`)
8. **Copy this ID** - this is what you need!

## Method 2: From Google Tag Manager

1. Go to [Google Tag Manager](https://tagmanager.google.com/)
2. Select your container
3. Go to **Tags** → Find your GA4 Configuration tag
4. Click on it
5. The **Measurement ID** should be visible in the tag configuration

## Method 3: Check Your Website Source Code

1. Open your website in a browser
2. Right-click → **View Page Source**
3. Search for `gtag` or `G-`
4. You should see something like: `gtag('config', 'G-XXXXXXXXXX')`
5. Copy the `G-XXXXXXXXXX` part

## Method 4: Check Your Frontend Environment Variables

If you have access to your frontend code:
- Look for `NEXT_PUBLIC_GA_ID` in your environment variables
- Or check `.env` files in your frontend project

## Once You Have It

1. Open `SiteSinc/Info.plist` in Xcode
2. Find the `GA_MEASUREMENT_ID` key
3. Replace `G-XXXXXXXXXX` with your actual Measurement ID:

```xml
<key>GA_MEASUREMENT_ID</key>
<string>G-XXXXXXXXXX</string>  <!-- Your actual ID here -->
```

## Important Notes

- **Same Property**: Your iOS app will send data to the same GA4 property as your website
- **Different Streams**: You can create a separate iOS data stream in GA4 if you want to separate mobile vs web data, but it's not required
- **Format**: The Measurement ID always starts with `G-` followed by 10 characters (letters and numbers)

## Still Can't Find It?

If you can't find your Measurement ID, you can:
1. Create a new GA4 property specifically for mobile (not recommended - better to use same one)
2. Or check with whoever set up your Google Analytics/Google Tag Manager

The Measurement ID is different from:
- ❌ Google Tag Manager Container ID (GTM-XXXXXXX)
- ❌ Google OAuth Client ID (ends in .apps.googleusercontent.com)
- ✅ GA4 Measurement ID (G-XXXXXXXXXX)
