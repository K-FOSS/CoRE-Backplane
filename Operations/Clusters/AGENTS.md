# Operations/Clusters documentation guidance

For `ENVIRONMENT.md` and other infrastructure documentation in this
directory, keep topology drawings synchronized with the prose and tables. Any
change that adds, removes, moves, or re-cables a device, interface, room path,
or network segment must update the relevant Mermaid topology diagram in the
same change. Use Mermaid diagrams so device relationships, ports, logical
bundles, and network segments remain readable and reviewable. Before finishing,
compare the diagram with the documented connection records and remove stale or
contradictory edges; do not leave layout changes represented only in prose.
