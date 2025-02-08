# K-FOSS/CoRE-Backplane IPAM Stack

This is a helm chart that deploys Netbox the open source DCIM offering, I've been running it for a few years, this chart uses my custom image that is built every day by my [K-FOSS/CoRE-Docker](https://github.com/K-FOSS/Core-Docker) repo

# Plugins

I use a few plugins

# Netbox-BGP

I really like the [Netbox-BGP](https://github.com/netbox-community/netbox-bgp) plugin, I use it to document all my internal BGP peering between sites and clusters.

# [Netbox-IP Calculator](https://github.com/PieterL75/netbox_ipcalculator)

In the past I have been using [ipcalc](https://jodies.de/ipcalc) for years, although it's nice to have a calulcator built right into the area **YOU SHOULD** have open while doing any network work anyways hehe.
