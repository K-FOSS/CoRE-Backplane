"""Route NetBox reads to the local PostgreSQL standby and writes to primary."""

import os
from contextvars import ContextVar

from django.conf import settings
from django.db import connections


_prefer_primary = ContextVar("netbox_prefer_primary", default=False)


if "replica" not in settings.DATABASES:
    raise RuntimeError("NetBox replica database alias is required")

# NetBox's chart reads the password Secret for DATABASES.default only. The
# replica password is injected separately from that same Secret through an
# environment variable, never rendered in Helm values or a ConfigMap.
replica_password = os.environ.get("NETBOX_REPLICA_DB_PASSWORD")
if not replica_password:
    raise RuntimeError("NetBox replica database password is required")

settings.DATABASES["replica"]["PASSWORD"] = replica_password
connections.databases["replica"]["PASSWORD"] = replica_password


class NetBoxDatabaseRouter:
    """Keep writes and consistency-sensitive reads on the global primary."""

    PRIMARY_READ_APPS = {"admin", "auth", "contenttypes", "sessions", "users"}

    def db_for_read(self, model, **hints):
        if model._meta.app_label in self.PRIMARY_READ_APPS:
            return "default"

        if _prefer_primary.get():
            return "default"

        for alias in ("default", "replica"):
            if connections[alias].in_atomic_block:
                return alias

        instance = hints.get("instance")
        if instance is not None and instance._state.db in {"default", "replica"}:
            return instance._state.db

        return "replica"

    def db_for_write(self, model, **hints):
        _prefer_primary.set(True)
        return "default"

    def allow_relation(self, obj1, obj2, **hints):
        if obj1._state.db in {"default", "replica"} and obj2._state.db in {
            "default",
            "replica",
        }:
            return True
        return None

    def allow_migrate(self, db, app_label, model_name=None, **hints):
        return db == "default"


class ReadReplicaRoutingMiddleware:
    """Use primary for unsafe HTTP requests and isolate request routing state."""

    SAFE_METHODS = {"GET", "HEAD", "OPTIONS"}

    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        token = _prefer_primary.set(request.method not in self.SAFE_METHODS)
        try:
            return self.get_response(request)
        finally:
            _prefer_primary.reset(token)
