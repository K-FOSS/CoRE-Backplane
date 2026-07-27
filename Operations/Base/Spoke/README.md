# Open Cluster Management spoke deployment

This chart creates OCM spoke-side Klusterlet, service account, registration
secrets and PushSecret/ExternalSecret resources.

No direct ApplicationSet owner was found. Values contain deployment-specific
hub API addresses; confirm the target hub and certificate authority before
use.

Registration credentials are high privilege. Protect and rotate them, validate
hub reachability and Klusterlet conditions, and define what happens to managed
resources when a spoke is detached or the hub is unavailable.
