{{/* Validate invariants that JSON Schema cannot express across DHCPv4 entries. */}}
{{- define "ipam.dhcp4.validate" -}}
{{- $config := required "dhcp.dhcp4 is required" .Values.dhcp.dhcp4 -}}
{{- $networkNames := dict -}}
{{- $subnetIDs := dict -}}
{{- $reservationIPs := dict -}}
{{- $reservationMACs := dict -}}
{{- $classNames := dict "tinkerbell" true "ipxe" true "pxe-legacy" true "pxe-uefi" true "ubnt" true -}}

{{- range $index, $class := default (list) (get $config "client-classes") -}}
  {{- $name := required (printf "dhcp.dhcp4.client-classes[%d].name is required" $index) $class.name -}}
  {{- if hasKey $classNames $name -}}
    {{- fail (printf "dhcp.dhcp4.client-classes contains duplicate or reserved name %q" $name) -}}
  {{- end -}}
  {{- $_ := set $classNames $name true -}}
{{- end -}}

{{- range $networkIndex, $network := required "dhcp.dhcp4.shared-networks must contain at least one network" (get $config "shared-networks") -}}
  {{- $networkName := required (printf "dhcp.dhcp4.shared-networks[%d].name is required" $networkIndex) $network.name -}}
  {{- if hasKey $networkNames $networkName -}}
    {{- fail (printf "dhcp.dhcp4.shared-networks contains duplicate name %q" $networkName) -}}
  {{- end -}}
  {{- $_ := set $networkNames $networkName true -}}

  {{- range $subnetIndex, $subnet := required (printf "dhcp.dhcp4.shared-networks[%d].subnet4 must not be empty" $networkIndex) $network.subnet4 -}}
    {{- $subnetID := required (printf "subnet ID is required for network %q subnet %d" $networkName $subnetIndex) $subnet.id | toString -}}
    {{- if hasKey $subnetIDs $subnetID -}}
      {{- fail (printf "dhcp.dhcp4 contains duplicate subnet ID %s" $subnetID) -}}
    {{- end -}}
    {{- $_ := set $subnetIDs $subnetID true -}}
    {{- $cidr := required (printf "subnet is required for network %q subnet ID %s" $networkName $subnetID) $subnet.subnet -}}
    {{- if not (regexMatch `^([0-9]{1,3}\.){3}[0-9]{1,3}/([0-9]|[12][0-9]|3[0-2])$` $cidr) -}}
      {{- fail (printf "dhcp.dhcp4 subnet ID %s has invalid IPv4 CIDR %q" $subnetID $cidr) -}}
    {{- end -}}

    {{- range $poolIndex, $pool := default (list) $subnet.pools -}}
      {{- $poolValue := required (printf "pool is required for subnet ID %s pool %d" $subnetID $poolIndex) $pool.pool -}}
      {{- if not (regexMatch `^([0-9]{1,3}\.){3}[0-9]{1,3}(/([0-9]|[12][0-9]|3[0-2])| - ([0-9]{1,3}\.){3}[0-9]{1,3})$` $poolValue) -}}
        {{- fail (printf "dhcp.dhcp4 subnet ID %s has invalid pool %q; use CIDR or 'start - end'" $subnetID $poolValue) -}}
      {{- end -}}
    {{- end -}}

    {{- range $reservationIndex, $reservation := default (list) $subnet.reservations -}}
      {{- $ip := required (printf "ip-address is required for subnet ID %s reservation %d" $subnetID $reservationIndex) (get $reservation "ip-address") -}}
      {{- if not (regexMatch `^([0-9]{1,3}\.){3}[0-9]{1,3}$` $ip) -}}
        {{- fail (printf "dhcp.dhcp4 subnet ID %s has invalid reservation IPv4 address %q" $subnetID $ip) -}}
      {{- end -}}
      {{- if hasKey $reservationIPs $ip -}}
        {{- fail (printf "dhcp.dhcp4 contains duplicate reservation IP %q" $ip) -}}
      {{- end -}}
      {{- $_ := set $reservationIPs $ip true -}}
      {{- with get $reservation "hw-address" -}}
        {{- $mac := lower . -}}
        {{- if not (regexMatch `^([0-9a-f]{2}:){5}[0-9a-f]{2}$` $mac) -}}
          {{- fail (printf "dhcp.dhcp4 subnet ID %s has invalid reservation MAC %q" $subnetID .) -}}
        {{- end -}}
        {{- if hasKey $reservationMACs $mac -}}
          {{- fail (printf "dhcp.dhcp4 contains duplicate reservation MAC %q" $mac) -}}
        {{- end -}}
        {{- $_ := set $reservationMACs $mac true -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- end -}}
