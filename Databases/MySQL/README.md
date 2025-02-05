# K-FOSS/CoRE-Backplane MySQL Stack

This deploys the Percona MySQL Database using the operator

## Initial Deployment

For an extremely annoying deployment you must comment out the LDAP configuration during initial deployment of the database cluster **ELSE IT WILL FAIL** it tries to load the plugin then decides not to during init then fails due to unexpected variables.

## TODO

Get S3 Backups online



