from django.db import models

class Product(models.Model):
    name = models.CharField(max_length=80)
    sku = models.CharField(max_length=40, default='')
