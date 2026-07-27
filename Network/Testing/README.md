# Network Testing chart

This chart deploys LibreSpeed, iperf3 and Gateway/traffic-policy test
resources. It is owned by `Apps/Network/Testing.yaml` and is deployed to
selected production clusters despite its testing purpose.

Use it to measure inter-site/cluster throughput and latency and to exercise
service, ingress, L2 announcement and LoadBalancer behavior.

Performance tests can consume significant CPU and bandwidth. Restrict
exposure, authenticate public tests, rate-limit where practical and schedule
high-bandwidth runs. Record direction, protocol, stream count, duration, MTU
and production load when comparing results.
