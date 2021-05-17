from django.core.management.base import BaseCommand
from django.contrib.auth.models import User
from typing import Any, Optional


class Command(BaseCommand):
    def handle(self, *args: Any, **options: Any) -> Optional[str]:
        User.objects.get_or_create(email="test@test.com")
        self.stdout.write(self.style.SUCCESS("User added"))
