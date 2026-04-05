# Homelab Bootstrap
Deployment scripts, Dockerfiles, configuration, and notes for bootstrapping Raspberry Pi and Mini-PC in my homelab.

## Quick Start
* Create `.env` file &rarr; check [.env.example](.env.example) for reference.
* Run `make setup-transmission` to set up Transmission

## Services
* [Pi-hole](services/pi-hole/pi-hole.yml)
* [Transmission](services/transmission/transmission.yml)

## Requirements
* Docker & Docker Compose
* Make
