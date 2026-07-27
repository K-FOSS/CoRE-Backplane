# Benchmarking deployment

This deployment defines storage benchmark classes, PVCs and Jobs and is owned
by `Apps/Operations/Benchmarking.yaml`.

Benchmarks are intended to characterize storage classes and node/storage paths,
not to establish a universal performance number. Record the cluster, node,
storage class, replica count, volume size, filesystem, test profile, duration
and concurrent load with every result.

Benchmark jobs can consume disk capacity, IOPS, CPU and network bandwidth and
can trigger Longhorn replica traffic or backend throttling. Use dedicated test
volumes, constrain placement, schedule disruptive tests and confirm cleanup.
Never point a destructive benchmark at a PVC containing application data.
