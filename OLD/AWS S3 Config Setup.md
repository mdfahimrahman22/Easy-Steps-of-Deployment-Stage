## AWS S3 Config Setup

1. Create a bucket and set this settings- 
	i) Permissions > Bucket policy:
```bash
{ 
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "PublicRead",
            "Effect": "Allow",
            "Principal": "*",
            "Action": [
                "s3:GetObject",
                "s3:GetObjectVersion"
            ],
            "Resource": "arn:aws:s3:::project-bucket-name/*"
        }
    ]
}
```

	ii) Permissions > Cross-origin resource sharing (CORS):
```bash
[
    {
        "AllowedHeaders": [
            "*"
        ],
        "AllowedMethods": [
            "POST",
            "GET",
            "PUT",
            "DELETE"
        ],
        "AllowedOrigins": [
            "*"
        ],
        "ExposeHeaders": []
    }
]
```

2. Install '**python-decouple**', '**boto3**' and '**django-storages**' packages

3. Add '**storages**' to INSTALLED_APPS in settings.py file

4. Add credentials to .env file like this -
```bash
AWS_ACCESS_KEY_ID= YOUR_AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY= YOUR_AWS_SECRET_ACCESS_KEY
AWS_STORAGE_BUCKET_NAME= YOUR_AWS_STORAGE_BUCKET_NAME
AWS_STORAGE_BUCKET_REGION=YOUR_AWS_STORAGE_BUCKET_REGION
USE_S3=True
```

5. Add these lines in **settings.py** file -

```bash
USE_S3 = config('USE_S3') == 'True'

STATICFILES_DIRS = [os.path.join(BASE_DIR, 'templates/assets')]

if USE_S3:
    # # aws settings
    AWS_S3_SIGNATURE_VERSION = 's3v4'
    AWS_S3_REGION_NAME = config('AWS_STORAGE_BUCKET_REGION')
    AWS_S3_ADDRESSING_STYLE = "virtual"
    AWS_S3_FILE_OVERWRITE = True
    AWS_DEFAULT_ACL = None
    AWS_ACCESS_KEY_ID = config('AWS_ACCESS_KEY_ID')
    AWS_SECRET_ACCESS_KEY = config('AWS_SECRET_ACCESS_KEY')
    AWS_STORAGE_BUCKET_NAME = config('AWS_STORAGE_BUCKET_NAME')
    AWS_S3_OBJECT_PARAMETERS = {'CacheControl': 'max-age=86400'}
    # # s3 static settings
    AWS_LOCATION = 'static'
    STATIC_URL = f'https://{AWS_STORAGE_BUCKET_NAME}.s3.amazonaws.com/{AWS_LOCATION}/'
    STATICFILES_STORAGE = 'core.storage_backends.StaticStorage'
    MEDIAFILES_LOCATION = 'media'
    MEDIA_URL = f'https://{AWS_STORAGE_BUCKET_NAME}.s3.amazonaws.com/{MEDIAFILES_LOCATION}/'
    DEFAULT_FILE_STORAGE = 'core.storage_backends.MediaStorage'
else:
    STATIC_URL = '/static/'
    STATIC_ROOT = os.path.join(BASE_DIR, 'static')
    MEDIA_URL = '/media/'
    MEDIA_ROOT = os.path.join(BASE_DIR, 'media') 

```

6. create **storage_backends.py** in 'core/' and add this line in the storage_backends.py-

```python
from storages.backends.s3boto3 import S3Boto3Storage

class MediaStorage(S3Boto3Storage):
    location = 'media'
    file_overwrite = False
    AWS_QUERYSTRING_AUTH = True

class StaticStorage(S3Boto3Storage):
    """Querystring auth must be disabled so that url() returns a consistent output."""
    querystring_auth = False
```

7. **Ref:** [Storing Django Static and Media Files on Amazon S3 | TestDriven.io](https://testdriven.io/blog/storing-django-static-and-media-files-on-amazon-s3/ "Storing Django Static and Media Files on Amazon S3 | TestDriven.io")


