.PHONY: env check-uid docker ssh mount-downloads config-transmission start-transmission bootstrap transmission

# Load .env so variables are available in all targets
-include .env

CURRENT_UID := $(shell id -u)
CURRENT_GID := $(shell id -g)

env:
	@if [ ! -f .env ]; then \
		cp .env.example .env; \
		echo "==> .env is created from .env.example"; \
		echo "    Review the file and update the placeholder values."; \
	fi

check-uid:
	@if [ "$(CURRENT_UID)" != "$(PUID)" ]; then \
		echo "WARN: id -u ($(CURRENT_UID)) differs from PUID in .env ($(PUID))"; \
		echo "      Mismatched uid/gid may cause volume permission errors."; \
		echo "      Update PUID/PGID in .env or re-run as the correct user."; \
	fi

docker:
	@echo "==> Installing Docker..."

ssh:
	@echo "==> Enabling SSH..."

bootstrap: env check-uid

mount-downloads:
	@echo "==> Creating mount points..."
	sudo mkdir -p /mnt/downloads
	sudo chown $(CURRENT_UID):$(CURRENT_GID) /mnt/downloads
	sudo chmod 2775 /mnt/downloads

	@echo "==> Installing automount units..."
	sudo cp configs/systemd/mnt-downloads.mount /etc/systemd/system/
	sudo cp configs/systemd/mnt-downloads.automount /etc/systemd/system/
	sudo systemctl daemon-reload

	@echo "==> Enabling automount units..."
	sudo systemctl enable --now mnt-downloads.automount

	@echo "==> Verifying..."
	systemctl status mnt-downloads.automount --no-pager

config-transmission:
	mkdir -p ${APPDATA}/transmission
	cp -r configs/transmission ${APPDATA}
	find $(APPDATA)/transmission -name ".gitkeep" -delete
	chmod -R 755 $(APPDATA)/transmission

start-transmission:
	docker compose --file docker-compose.yml up --detach --remove-orphans transmission

transmission: mount-downloads config-transmission start-transmission
