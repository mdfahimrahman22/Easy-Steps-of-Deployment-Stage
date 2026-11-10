# AWS CloudFront + S3 CDN Setup Guide

This guide details how to set up **AWS CloudFront** with an **AWS S3 bucket** using **Origin Access Control (OAC)** and attach a **Custom Domain with SSL (HTTPS)**.

---

## 1. Overview & Architecture

- **S3 Bucket (Private Storage)**: Holds audio files, images, videos, and student/user uploads. Public access remains blocked (`Block all public access` enabled).
- **Origin Access Control (OAC)**: Securely authorizes only CloudFront to read files from the private S3 bucket.
- **CloudFront (Global CDN)**: Caches assets at edge locations globally for ultra-low latency, fast streaming, and lower bandwidth costs.
- **Custom Domain & SSL**: Serves assets over HTTPS via your branded subdomain (e.g., `ielts-assets.smartsohay.com`).

---

## 2. Step 1: Request Free SSL Certificate in ACM

> **CRITICAL RULE**: CloudFront requires public SSL certificates to be in the **`us-east-1` (US East - N. Virginia)** region, regardless of your S3 bucket's region.

1. Open the [AWS Certificate Manager (ACM)](https://console.aws.amazon.com/acm/home).
2. Switch region to **US East (N. Virginia) `us-east-1`** in the top navigation bar.
3. Click **Request certificate** -> **Request a public certificate** -> **Next**.
4. **Domain names**:
   - For a single-level subdomain under an existing wildcard certificate (e.g., `*.smartsohay.com`), you can reuse it for domains like `ielts-assets.smartsohay.com`.
   - If using a two-level subdomain (e.g., `assets.ielts.smartsohay.com`), request a certificate specifically for `assets.ielts.smartsohay.com` or `*.ielts.smartsohay.com`.
     *(Note: An SSL wildcard `*.domain.com` covers only one level of subdomain, not two).*
5. Validation method: **DNS validation** -> Click **Request**.
6. Open the newly created certificate, copy the **CNAME name** and **CNAME value**, and add them to your DNS provider (Cloudflare, cPanel, Namecheap, etc.).
7. Wait until the Status turns green: **Issued**.

---

## 3. Step 2: Configure S3 CORS

Go to **AWS S3 Console** -> select your bucket -> **Permissions** tab -> scroll down to **Cross-origin resource sharing (CORS)** -> click **Edit**.

Paste the following JSON and click **Save changes**:

```json
[
  {
    "AllowedHeaders": [
      "*"
    ],
    "AllowedMethods": [
      "GET",
      "HEAD",
      "PUT",
      "POST"
    ],
    "AllowedOrigins": [
      "http://localhost:3000",
      "http://localhost:3001",
      "https://*.smartsohay.com"
    ],
    "ExposeHeaders": [
      "ETag"
    ],
    "MaxAgeSeconds": 3600
  }
]
```
*(During initial development or testing, you can use `"AllowedOrigins": ["*"]`)*.

---

## 4. Step 3: Create CloudFront Distribution

1. Open the [AWS CloudFront Console](https://console.aws.amazon.com/cloudfront/v4/home) and click **Create distribution**.

### Origin Settings:
- **Origin domain**: Click **Browse S3** and select your S3 bucket, or enter its regional endpoint:
  ```text
  your-bucket-name.s3.ap-southeast-1.amazonaws.com
  ```
- **Origin access**: Select **Origin access control settings (recommended)**.
- Click **Create new OAC**:
  - Name: Auto-filled (e.g., `your-bucket-name.s3.ap-southeast-1.amazonaws.com`)
  - Signing behavior: **Sign requests (recommended)**
  - Click **Create**.

### Default Cache Behavior:
- **Viewer protocol policy**: **Redirect HTTP to HTTPS**
- **Allowed HTTP methods**: **GET, HEAD, OPTIONS** *(Essential for audio streaming & browser CORS)*
- **Cache key and origin requests**:
  - **Cache policy**: Select **`Managed-CachingOptimized`**
  - **Origin request policy**: Select **`Managed-CORS-S3Origin`**
  - **Response headers policy**: Select **`Managed-CORS-S3Origin`** or **`Managed-CORS-with-preflight-and-SecurityHeadersPolicy`**

### Settings:
- **Price class**: Choose *Use all edge locations* (or *North America, Europe, Asia*)
- **Alternate domain name (CNAME)**: Click **Add item** and enter your custom domain:
  ```text
  ielts-assets.smartsohay.com
  ```
- **Custom SSL certificate**: Select your issued ACM certificate (e.g., `*.smartsohay.com` or custom).
- Click **Create distribution**.

---

## 5. Step 4: Update S3 Bucket Policy for CloudFront OAC

Immediately after creating the distribution, CloudFront will display a yellow banner:
> *"The S3 bucket policy needs to be updated. Copy policy"*

1. Click **Copy policy**, or use the template below:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowCloudFrontServicePrincipalReadOnly",
      "Effect": "Allow",
      "Principal": {
        "Service": "cloudfront.amazonaws.com"
      },
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::your-bucket-name/*",
      "Condition": {
        "StringEquals": {
          "AWS:SourceArn": "arn:aws:cloudfront::<YOUR_AWS_ACCOUNT_ID>:distribution/<YOUR_CLOUDFRONT_DISTRIBUTION_ID>"
        }
      }
    }
  ]
}
```

2. Open **AWS S3 Console** -> Your Bucket -> **Permissions** -> **Bucket policy** -> **Edit**.
3. Paste the policy and click **Save changes**.

---

## 6. Step 5: Configure Cloudflare DNS (Step-by-Step)

Since your domain DNS is managed by **Cloudflare**, follow these exact steps to connect your subdomain to CloudFront:

### 1. Open Cloudflare Dashboard
1. Log in to [Cloudflare Dashboard](https://dash.cloudflare.com/).
2. Select your domain: **`smartsohay.com`**.
3. In the left sidebar, click **DNS** -> **Records**.

### 2. Add CNAME Record for CloudFront
1. Click the blue **Add record** button.
2. Fill in the following fields:

| Setting | Value / Selection | Description |
| :--- | :--- | :--- |
| **Type** | `CNAME` | Select CNAME from the dropdown |
| **Name (required)** | `ielts-assets` | Type just `ielts-assets` (Cloudflare will display `ielts-assets.smartsohay.com`) |
| **Target (required)** | `dXXXXXXXXXXXXX.cloudfront.net` | Paste your CloudFront Distribution Domain Name (from CloudFront General tab) |
| **Proxy status** | **DNS only** (Grey Cloud ⚪) | **CRITICAL:** Click the orange cloud icon to turn it off (Grey / DNS Only) |
| **TTL** | `Auto` | Default is fine |

3. Click **Save**.

> ⚠️ **IMPORTANT (Why DNS Only?):**  
> CloudFront already acts as an edge CDN with its own caching and AWS ACM SSL certificate. If you keep the Cloudflare proxy (Orange Cloud 🟠) enabled, Cloudflare and CloudFront will double-proxy each other, which causes SSL certificate mismatch errors or redirect loops. Always use **DNS only (Grey Cloud ⚪)** for CloudFront CNAME records.

---

### 3. Adding ACM SSL Certificate Validation Record in Cloudflare (If creating a new certificate)

Whenever you request a new certificate in AWS ACM (in `us-east-1`), AWS provides a validation CNAME. Add it to Cloudflare as follows:

1. In ACM, note the **CNAME name** and **CNAME value** (e.g., `_a7b8c...smartsohay.com.` -> `_x9y8z...acm-validations.aws.`).
2. In Cloudflare **DNS** -> **Records** -> **Add record**:
   - **Type**: `CNAME`
   - **Name**: The part before `.smartsohay.com` (or paste the full CNAME name, Cloudflare trims it automatically)
   - **Target**: The full CNAME value ending with `.acm-validations.aws.`
   - **Proxy status**: **DNS only** (Grey Cloud ⚪)
   - **TTL**: `Auto`
3. Click **Save**. AWS ACM will validate and issue the certificate within 1–3 minutes.

---

### 4. Verify DNS Propagation

Run either of these commands in your terminal to verify that the subdomain points to CloudFront:

```bash
# Using nslookup
nslookup ielts-assets.smartsohay.com

# Or using PowerShell
Resolve-DnsName ielts-assets.smartsohay.com
```

If configured correctly, the answer will resolve to your CloudFront distribution domain (`dXXXXXXXX.cloudfront.net`) and its edge IP addresses.

---

## 7. Step 6: Use in Application / Monorepo

### 1. Environment Variables (`.env`)

```env
# S3 Credentials for uploads
STORAGE_ENDPOINT=
STORAGE_REGION=ap-southeast-1
STORAGE_BUCKET=your-bucket-name
STORAGE_ACCESS_KEY_ID=AKIAXXXXXXXXXXXXXXXX
STORAGE_SECRET_ACCESS_KEY=your_secret_access_key

# Public CDN URL for serving assets
STORAGE_CDN_URL=https://ielts-assets.smartsohay.com
```

*Leave `STORAGE_ENDPOINT=` empty when using native AWS S3 (AWS SDK resolves endpoints automatically).*

### 2. Next.js Image Optimization (`next.config.ts`)

Add the CDN hostname and CloudFront pattern to `images.remotePatterns` to allow Next.js `<Image />` optimization:

```ts
const cdnHostname = process.env.STORAGE_CDN_URL
  ? (() => {
      try {
        return new URL(process.env.STORAGE_CDN_URL).hostname;
      } catch {
        return null;
      }
    })()
  : null;

const nextConfig: NextConfig = {
  images: {
    remotePatterns: [
      { protocol: "https", hostname: "*.cloudfront.net" },
      ...(cdnHostname ? [{ protocol: "https" as const, hostname: cdnHostname }] : []),
    ],
  },
};
```

---

## 8. Verification & Testing

1. **Verify Asset Delivery via CloudFront**:
   ```bash
   curl -I https://ielts-assets.smartsohay.com/sample-audio.mp3
   ```
   Look for:
   - `HTTP/2 200` (or `206 Partial Content`)
   - `x-cache: Hit from cloudfront` (or `Miss from cloudfront` on the first request)

2. **Verify S3 Private Access**:
   Accessing the raw S3 URL directly in a browser:
   `https://your-bucket-name.s3.ap-southeast-1.amazonaws.com/sample-audio.mp3`
   Should return `<Code>AccessDenied</Code>`, confirming the S3 bucket is securely protected and accessible only via CloudFront.
