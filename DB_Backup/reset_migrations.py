import os
import shutil
import django
from django.db import connection

# Set up Django environment
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'core.settings')
try:
    django.setup()
except Exception as e:
    print(f"Warning: Could not setup Django (expected if environment is broken): {e}")

def reset_migrations():
    base_dir = os.getcwd()
    
    print("Starting migration and pycache cleanup...")
    
    for root, dirs, files in os.walk(base_dir):
        # Exclude venv and hidden directories (like .git)
        dirs[:] = [d for d in dirs if d not in ['venv', 'env'] and not d.startswith('.')]
        
        # 1. Delete __pycache__ folders
        if '__pycache__' in dirs:
            pycache_path = os.path.join(root, '__pycache__')
            print(f"Deleting: {pycache_path}")
            shutil.rmtree(pycache_path)
        
        # 2. Delete migration files except __init__.py
        if os.path.basename(root) == 'migrations':
            for file in files:
                if file != '__init__.py' and file.endswith('.py'):
                    file_path = os.path.join(root, file)
                    print(f"Deleting migration: {file_path}")
                    os.remove(file_path)

    # 3. Delete migration data from database
    print("\nCleaning up database migration history...")
    try:
        with connection.cursor() as cursor:
            # This deletes all records from the django_migrations table
            cursor.execute("DELETE FROM django_migrations;")
            print("Successfully cleared 'django_migrations' table.")
    except Exception as e:
        print(f"Error cleaning database: {e}")
        print("Note: If the database is not accessible, you may need to run 'DELETE FROM django_migrations;' manually.")

    print("\nCleanup complete.")
    print("Next steps (run manually):")
    print("1. python manage.py makemigrations")
    print("2. python manage.py migrate --fake")

if __name__ == "__main__":
    # Note: As requested, this script is created but not executed.
    # To run it, execute: python reset_migrations.py
    reset_migrations()
