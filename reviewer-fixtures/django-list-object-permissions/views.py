from rest_framework.permissions import BasePermission, IsAuthenticated
from rest_framework.serializers import ModelSerializer
from rest_framework.viewsets import ReadOnlyModelViewSet
from .models import Item

class IsOwner(BasePermission):
    def has_object_permission(self, request, view, obj):
        return obj.owner_id == request.user.pk

class ItemSerializer(ModelSerializer):
    class Meta:
        model = Item
        fields = ['id', 'title']

class ItemViewSet(ReadOnlyModelViewSet):
    queryset = Item.objects.all()
    serializer_class = ItemSerializer
    permission_classes = [IsAuthenticated, IsOwner]
