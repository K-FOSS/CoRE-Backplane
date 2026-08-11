{{/* Validate DHCPv6 invariants that JSON Schema cannot express across entries. */}}
{{- define "ipam.dhcp6.validate" -}}
{{- $config := required "dhcp.dhcp6 is required" .Values.dhcp.dhcp6 -}}
{{- $subnetIDs := dict -}}

{{- range $index, $subnet := default (list) (get $config "subnet6") -}}
  {{- $subnetID := required (printf "dhcp.dhcp6.subnet6[%d].id is required" $index) $subnet.id | toString -}}
  {{- if hasKey $subnetIDs $subnetID -}}
    {{- fail (printf "dhcp.dhcp6 contains duplicate subnet ID %s" $subnetID) -}}
  {{- end -}}
  {{- $_ := set $subnetIDs $subnetID true -}}
  {{- $cidr := required (printf "dhcp.dhcp6 subnet ID %s requires subnet" $subnetID) $subnet.subnet -}}
  {{- if regexMatch `(?i)^2001:db8:` $cidr -}}
    {{- fail (printf "dhcp.dhcp6 subnet ID %s uses documentation-only prefix %q" $subnetID $cidr) -}}
  {{- end -}}
  {{- range $poolIndex, $pool := default (list) $subnet.pools -}}
    {{- required (printf "dhcp.dhcp6 subnet ID %s pool %d requires pool" $subnetID $poolIndex) $pool.pool -}}
  {{- end -}}
  {{- range $poolIndex, $pool := default (list) (get $subnet "pd-pools") -}}
    {{- required (printf "dhcp.dhcp6 subnet ID %s delegated pool %d requires prefix" $subnetID $poolIndex) $pool.prefix -}}
    {{- required (printf "dhcp.dhcp6 subnet ID %s delegated pool %d requires prefix-len" $subnetID $poolIndex) (get $pool "prefix-len") -}}
    {{- required (printf "dhcp.dhcp6 subnet ID %s delegated pool %d requires delegated-len" $subnetID $poolIndex) (get $pool "delegated-len") -}}
  {{- end -}}
{{- end -}}
{{- end -}}
