# Homelab Bootstrap
Deployment scripts, Dockerfiles, configuration, and notes for bootstrapping Raspberry Pi and Mini-PC in my homelab.

## Quick Start
* Create `.env` file &rarr; check [.env.example](.env.example) for reference.
* Run `make setup-transmission` to set up Transmission

## Services
* [Pi-hole](services/pi-hole/pi-hole.yml) – Network-wide Ad Blocking
* [Torrentino](services/torrentino/torrentino.yml) – Telegram Bot for Transmission 
* [Traefik](services/traefik/traefik.yml) – Reverse Proxy
* [Transmission](services/transmission/transmission.yml) – BitTorrent Client

## Requirements
* Make
```bash
sudo apt-get install --no-install-recommends -y make
```

* Docker & Docker Compose
```bash
make setup-docker
```
