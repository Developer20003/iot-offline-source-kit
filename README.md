# Offline IoT Development Kit

A source-editable development environment for an IoT platform.

## Components

- EMQX Enterprise 6.3.1
- Apache Kafka 4.2.2
- ThingsBoard CE 4.3.1.6
- Zigbee2MQTT 2.14.2
- PostgreSQL 17
- Python BLE-to-MQTT gateway

## Project goals

Run, edit, rebuild, and maintain the platform without internet
access after all prerequisites and release assets are installed.

## Downloads

Large source bundles, build dependencies, Docker images, and
compiled applications will be distributed as GitHub Release assets.

## Offline installation

After downloading all release assets into their documented
offline-bundle directories:

1. Run offline-bundle/bootstrap-offline.sh --extract
2. Run scripts/restore-complete-offline-kit.sh --verify
3. Restore the development kit to a new destination.
4. Prepare Docker, Kafka, and PostgreSQL.
5. Start the services and verify functionality.

## Verification status

Offline source and dependency restoration tests passed.
Offline startup and clean rebuild testing on the second laptop
are not yet complete. Zigbee and BLE hardware tests are pending.

## Security

Never publish database dumps, passwords, cookies, private
configuration files, runtime data, or device credentials.

## Third-party licenses

All upstream components retain their original licenses.
EMQX 6.3.1 is source-available under BSL 1.1.
Redistribution must comply with applicable license terms.
