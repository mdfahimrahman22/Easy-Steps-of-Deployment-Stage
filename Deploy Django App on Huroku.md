# Django App Deploy on Heroku

- Heroku login
``
heroku login
heroku git:remote -a ktcommerce-django
``

- create 'runtime.txt' and add python-version like this:
> python-3.9.4

- create Procfile without any extension and add-
> web: gunicorn core.wsgi --log-file -

- change settings of your app like this:
> DEBUG = False
ALLOWED_HOSTS = ['YourHerokuAppIp','127.0.0.1']

- & also change the **SECRET_KEY**

- Goto 'Settings' of your heroku app and press 'Add buildpack',
then select python and save changes

- Create github repository in github

- Add this line to your settings.py to handle static files

	> STATIC_ROOT=os.path.join(BASE_DIR,'staticfiles')

- Install whitenoise and add this middlewire in your app's settings.py
> 'whitenoise.middleware.WhiteNoiseMiddleware',

**Note:** Make sure gunicorn and whitenoise package are mentioned in requirements.txt file

- #### Goto '**Deploy**' of your heroku app and connect your git repo (search your repo then connect)
