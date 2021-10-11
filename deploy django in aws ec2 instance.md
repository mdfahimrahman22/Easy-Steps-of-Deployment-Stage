### **Deploy Django App in Remote Server**
1 . Server Update
```shell
sudo apt-get update
sudo apt-get upgrade -y
```
2 . Install venv
`sudo apt-get install python3-venv -y`

3 . Clone the project and navigate to the project folder

4 . Create vertual env and activate it
```shell
python3 -m venv venv
source venv/bin/activate
```
5 .  `sudo apt install gunicorn`

6 . `sudo apt-get install -y nginx`

> [**Note:** If you want to install dlib/face-recognition library do not use vertual env. Workon system installed python3 and install them when your are at the root path otherwise you will get errors. If you want to deploy your app on AWS EC2 instance with these ML packages you need atleast t2.medium ]

## Configure security group on AWS
[![Security Group Configuration](https://drive.google.com/uc?export=view&id=1qi1VdGI1sLwAskhAqSmHYGE0D9Cs5mNj "Security Group Configuration")](https://drive.google.com/uc?export=view&id=1qi1VdGI1sLwAskhAqSmHYGE0D9Cs5mNj "Security Group Configuration")

[![Security Group Configuration](https://drive.google.com/uc?export=view&id=1i8UNYvNnuvMIbPmDJj9gIolv5YHjvTzs "Security Group Configuration")](https://drive.google.com/uc?export=view&id=1i8UNYvNnuvMIbPmDJj9gIolv5YHjvTzs "Security Group Configuration")

[![Security Group Configuration](https://drive.google.com/uc?export=view&id=17i2YH4_xLSw3RZQlOZuWD1oTHuLA3j3R "Security Group Configuration")](https://drive.google.com/uc?export=view&id=17i2YH4_xLSw3RZQlOZuWD1oTHuLA3j3R "Security Group Configuration")

[![Security Group Configuration](https://drive.google.com/uc?export=view&id=17mBkKsyZfXBoTIVc97O7VMWh5xpY-QFz "Security Group Configuration")](https://drive.google.com/uc?export=view&id=17mBkKsyZfXBoTIVc97O7VMWh5xpY-QFz "Security Group Configuration")

## Start nginx
7 . `sudo nginx`

If you see this kind of error -
```shell
ubuntu@ip-172-31-28-221:~/adobe-face-recognition-api-django$ sudo nginx
nginx: [emerg] bind() to 0.0.0.0:80 failed (98: Address already in use)
nginx: [emerg] bind() to [::]:80 failed (98: Address already in use)
nginx: [emerg] bind() to 0.0.0.0:80 failed (98: Address already in use)
...
```
Then use these commands- 
```shell
sudo pkill -f nginx & wait $!
sudo systemctl start nginx
```
Still same problem! Check [Here](https://www.digitalocean.com/community/questions/nginx-not-starting-address-already-in-use-nginx-bind-to-0-0-0-0-80-failed "here")

8 . `gunicorn --bind 0.0.0.0:8080 core.wsgi:application`

### Creating supervisor, it will make sure your app is up-end running
1 . 
````shell
sudo apt-get install -y supervisor
cd /etc/supervisor/conf.d/
sudo touch gunicorn.conf
sudo nano gunicorn.conf
````
2 . Paste these lines- [Make sure you change 'ProjectFolderName' to your corresponding app folder]

```shell
[program:gunicorn]
directory=/home/ubuntu/ProjectFolderName
command=/home/ubuntu/ProjectFolderName/venv/bin/gunicorn --workers 3 --bind unix:/home/ubuntu/ProjectFolderName/app.sock core.wsgi:application
autostart=true
autorestart=true
stderr_logfile=/var/log/gunicorn/gunicorn.err.log
stdout_logfile=/var/log/gunicorn/gunicorn.out.log
[group:guni]
programs:gunicorn
```
Make your changes and press CTRL+O and Enter to save then CTRL+X to exit

  3 . 
```shell
sudo mkdir /var/log/gunicorn
sudo supervisorctl reread
sudo supervisorctl update
sudo supervisorctl status
cd
cd /etc/nginx/sites-available/
sudo touch django.conf
sudo nano django.conf
```
4 . Paste these lines-
```shell
server{
    listen 8080;
    server_name ec2-13-213-38-171.ap-southeast-1.compute.amazonaws.com;

    location / {
     include proxy_params;
     proxy_pass http://unix:/home/ubuntu/ProjectFolderName/app.sock;
        
}
}
```
5 . 
`sudo nano /etc/nginx/nginx.conf`

6 . Add this at the top of http block- 
`server_names_hash_bucket_size  164;`

Or, Uncomment this - 
`server_names_hash_bucket_size 64;`
And increase the size like this -
`server_names_hash_bucket_size 164;`

7 . 
```shell
cd /etc/nginx/sites-available/
sudo nginx -t
sudo ln -S django.conf /etc/nginx/sites-enabled/
sudo ln django.conf /etc/nginx/sites-enabled/
sudo service nginx restart
```

##Static files serving

1. `sudo nano /etc/nginx/sites-available/django.conf`
2. And add the static location location-
```shell
location /static/{
autoindex on;
alias /home/ubuntu/ProjectFolderName/staticfiles/;
}
```

###Reload the nginx
2. `sudo systemctl reload nginx`

##Media file serving
> same as static file serving..Just add the media files location-

```shell
location /Data/{
alias /home/ubuntu/AmariBlog-Django/Data/;
}
```

##To reload supervisor
1. `sudo supervisorctl reload`

If it is too much difficult for you to understand this documentation you can follow [This tutorial](https://youtu.be/u0oEIqQV_-E)
