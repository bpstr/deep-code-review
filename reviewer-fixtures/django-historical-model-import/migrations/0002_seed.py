from django.db import migrations
from shop.models import Product

def seed(apps, schema_editor):
    Product.objects.create(name='Starter')

class Migration(migrations.Migration):
    dependencies = [('shop', '0001_initial')]
    operations = [migrations.RunPython(seed, migrations.RunPython.noop)]
