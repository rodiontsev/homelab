.PHONY: help validate-env \
	setup-docker \
	setup-ssh \
	setup-transmission start-transmission stop-transmission \
	start-torrentino stop-torrentino \
	setup-nginx help-nginx

# Load .env so variables are available in all targets
-include .env

CURRENT_UID := $(shell id -u)
CURRENT_GID := $(shell id -g)

# Colors for output
RED := \033[0;31m
GREEN := \033[0;32m
YELLOW := \033[0;33m
BLUE := \033[0;34m
NC := \033[0m # No Color

NGINX_WEB_ROOT=/var/www/$(DOMAIN_NAME)

.DEFAULT_GOAL := help

# Logging functions
define log_header
	printf "$(GREEN)%s...$(NC)\n" "$(1)"
endef

define log_step
	printf "$(BLUE)• %s$(NC)\n" "$(1)"
endef

define log_done
	printf "$(GREEN)✓ %s$(NC)\n" "$(1)"
endef

define log_warn
	printf "$(YELLOW)‼︎ %s$(NC)\n" "$(1)"
endef

define log_error
	printf "$(RED)✗ %s$(NC)\n" "$(1)"
endef

# 1 - protocol name (HTTP or HTTPS)
# 2 - port number (80 or 443)
# 3 - iptables rule position (5 for HTTP, 6 for HTTPS)
define open_port
	if ! ./scripts/check_port.sh "$(DOMAIN_NAME)" "$(2)"; then \
		$(call log_step,Configuring firewall for $(1)); \
		sudo iptables -I INPUT $(3) -m state --state NEW -p tcp --dport $(2) -j ACCEPT; \
		sudo iptables -L INPUT -v -n --line-numbers; \
		read -p "Save iptables configuration? [y/N] " confirm; \
		if [ "$$confirm" = "y" ] || [ "$$confirm" = "Y" ]; then \
			$(call log_step,Saving configuration); \
			sudo netfilter-persistent save; \
		else \
			$(call log_warn,Configuration not saved - will be lost on reboot); \
		fi; \
		if ! ./scripts/check_port.sh "$(DOMAIN_NAME)" "$(2)"; then \
			$(call log_error,Port $(2) still blocked - check cloud firewall); \
			exit 1; \
		fi; \
		$(call log_done,Port $(2) now accessible); \
	else \
		$(call log_done,Port $(2) already accessible); \
	fi
endef

define certbot
	sudo certbot certonly \
		$(if $(filter dry-run,$(1)),--dry-run,) \
		--webroot \
		--webroot-path $(NGINX_WEB_ROOT)/acme \
		--email $(LETS_ENCRYPT_EMAIL) \
		--domain $(DOMAIN_NAME) \
		--domain www.$(DOMAIN_NAME) \
		--deploy-hook "systemctl reload nginx" \
		--non-interactive \
		--agree-tos
endef

help:
	@printf "$(GREEN)Available targets:$(NC)"
	@printf "$(BLUE)  • setup-transmission$(NC)     - Set up Transmission BitTorrent client"
	@printf "$(BLUE)  • start-transmission$(NC)     - Start Transmission"
	@printf "$(BLUE)  • stop-transmission$(NC)      - Stop Transmission"
	@printf "$(BLUE)  • start-torrentino$(NC)       - Start Torrentino Telegram bot"
	@printf "$(BLUE)  • stop-torrentino$(NC)        - Stop Torrentino"
	@printf "$(BLUE)  • setup-nginx$(NC)            - Set up Nginx with Let's Encrypt SSL"

validate-env:
	@$(call log_header,Verifying environment)

	@$(call log_step,Verifying .env file)
	@if [ ! -f .env ]; then \
		cp .env.example .env; \
		$(call log_warn,Created .env from .env.example); \
		echo "  Review and update placeholder values before proceeding."; \
		exit 1; \
	fi

	@$(call log_step,Verifying environment variables)
	@if [ "$(CURRENT_UID)" != "$(PUID)" ]; then \
		$(call log_warn,id -u ($(CURRENT_UID)) differs from PUID in .env ($(PUID))); \
		echo "  Mismatched uid/gid may cause volume permission errors"; \
		echo "  Update PUID/PGID in .env or re-run as the correct user"; \
		exit 1; \
	fi

	@$(call log_done,Environment ready)

setup-docker:
	@$(call log_header,Setting up Docker)
	@$(call log_warn,Not yet implemented)

setup-ssh:
	@$(call log_header,Setting up SSH)
	@$(call log_warn,Not yet implemented)

setup-transmission: validate-env
	@$(call log_header,Setting up Transmission)

	@$(call log_step,Creating mount points)
	@sudo mkdir -p /mnt/downloads
	@sudo chown $(CURRENT_UID):$(CURRENT_GID) /mnt/downloads
	@sudo chmod 2775 /mnt/downloads

	@$(call log_step,Installing automount units)
	@sudo cp configs/systemd/mnt-downloads.mount /etc/systemd/system/
	@sudo cp configs/systemd/mnt-downloads.automount /etc/systemd/system/
	@sudo systemctl daemon-reload

	@$(call log_step,Enabling automount)
	@sudo systemctl enable --now mnt-downloads.automount

	@$(call log_step,Verifying automount status)
	@systemctl is-active mnt-downloads.automount --quiet \
		|| ($(call log_error,Automount unit not active) && exit 1)

	@$(call log_step,Creating configuration files)
	@mkdir -p $(APPDATA)/transmission
	@cp -r configs/transmission $(APPDATA)
	@find $(APPDATA)/transmission -name ".gitkeep" -delete
	@chmod -R 755 $(APPDATA)/transmission

	@$(call log_done,Transmission ready)

start-transmission:
	@$(call log_header,Starting Transmission)
	@docker compose --file docker-compose.yml up --detach --remove-orphans transmission
	@$(call log_done,Transmission started)

stop-transmission:
	@$(call log_header,Stopping Transmission)
	@docker compose --file docker-compose.yml stop transmission

stop-transmission:
	@echo "$(GREEN)Stopping Transmission...$(NC)"
	@docker compose --file docker-compose.yml stop transmission

start-torrentino:
	@$(call log_header,Starting Torrentino)
	@docker compose --file docker-compose.yml up --detach --remove-orphans torrentino
	@$(call log_done,Torrentino started)

stop-torrentino:
	@$(call log_header,Stopping Torrentino)
	@docker compose --file docker-compose.yml stop torrentino

stop-torrentino:
	@echo "$(GREEN)Stopping Torrentino...$(NC)"
	@docker compose --file docker-compose.yml stop torrentino

help-nginx:
	@$(call log_warn,Before proceeding:)
	@echo "  • Ensure ports 80 and 443 are open in the cloud firewall"
	@echo "  • Verify DNS A/AAAA records point to this server"
	@echo ""
	@printf "$(BLUE)Cloud Provider Documentation:$(NC)"
	@echo "  • Oracle Cloud: https://docs.oracle.com/en-us/iaas/Content/developer/apache-on-ubuntu/01oci-ubuntu-apache-summary.htm#add-ingress-rules"
	@echo ""
	@read -p "Continue? [y/N] " confirm; \
	if [ "$$confirm" != "y" ] && [ "$$confirm" != "Y" ]; then \
		$(call log_error,Aborted); \
		exit 1; \
	fi

setup-nginx: help-nginx validate-env
	@$(call log_header,Setting up Nginx with Let's Encrypt SSL)

	@test -x ./scripts/check_port.sh \
		|| ($(call log_error,Script not found or not executable: scripts/check_port.sh) && exit 1)
	@test -x ./scripts/check_redirect.sh \
		|| ($(call log_error,Script not found or not executable: scripts/check_redirect.sh) && exit 1)

	@$(call log_step,Installing Nginx and Certbot)
	@sudo apt-get update && \
		sudo apt-get install --no-install-recommends -y \
			nginx=1.24\* \
			certbot=2.9\* \
			ssl-cert

	@$(call log_step,Verifying installations)
	@systemctl is-active nginx --quiet \
		|| ($(call log_error,Nginx is not running) && exit 1)
	@command -v certbot > /dev/null 2>&1 \
		|| ($(call log_error,certbot command not found) && exit 1)

	@$(call log_step,Creating web root and ACME directories)
	@sudo mkdir -p $(NGINX_WEB_ROOT)/html
	@sudo mkdir -p $(NGINX_WEB_ROOT)/acme/.well-known/acme-challenge
	@echo "Hello, World!" | sudo tee $(NGINX_WEB_ROOT)/html/index.html > /dev/null

	@sudo chown -R $(CURRENT_UID):$(CURRENT_GID) $(NGINX_WEB_ROOT)/html
	@sudo chmod -R 755 $(NGINX_WEB_ROOT)

	@$(call log_step,Installing Nginx SSL configuration)
	@sudo cp configs/nginx/snippets/security.conf /etc/nginx/snippets
	@sudo cp configs/nginx/snippets/ssl.conf /etc/nginx/snippets
	@sudo sed 's|example.com|$(DOMAIN_NAME)|g' configs/nginx/sites-available/example.com \
		| sudo tee /etc/nginx/sites-available/$(DOMAIN_NAME) > /dev/null

	@$(call log_step,Creating temporary self-signed certificates)
	@sudo mkdir -p /etc/nginx/ssl
	@sudo ln -sf /etc/ssl/certs/ssl-cert-snakeoil.pem /etc/nginx/ssl/fullchain.pem
	@sudo ln -sf /etc/ssl/private/ssl-cert-snakeoil.key /etc/nginx/ssl/privkey.pem

	@$(call log_step,Creating Diffie-Hellman parameters file)
	@read -p "Use pre-generated DH parameters? (faster, generates new if no) [y/N] " confirm; \
	if [ "$$confirm" = "y" ] || [ "$$confirm" = "Y" ]; then \
		$(call log_step,Using pre-generated DH parameters); \
		sudo cp configs/nginx/ssl/dhparams.pem /etc/nginx/ssl; \
	else \
		$(call log_step,Generating new DH parameters (this may take several minutes)); \
		sudo openssl dhparam -out /etc/nginx/ssl/dhparams.pem 4096; \
	fi

	@$(call log_step,Disabling default site)
	@sudo rm -f /etc/nginx/sites-enabled/default

	@$(call log_step,Enabling $(DOMAIN_NAME))
	@sudo ln -sf /etc/nginx/sites-available/$(DOMAIN_NAME) /etc/nginx/sites-enabled/

	@$(call log_step,Testing Nginx configuration)
	@sudo nginx -t || ($(call log_error,Nginx configuration test failed) && exit 1)

	@$(call log_step,Restarting Nginx)
	@sudo systemctl restart nginx

	@$(call log_step,Configuring firewall for HTTP and HTTPS)
	@$(call open_port,HTTP,80,5)
	@$(call open_port,HTTPS,443,6)

	@$(call log_step,Testing Let's Encrypt configuration (dry run))
	@$(call certbot,dry-run)

	@$(call log_step,Obtaining Let's Encrypt certificates)
	@$(call certbot)

	@$(call log_step,Replacing self-signed certificates with Let's Encrypt certificates)
	@sudo rm -f /etc/nginx/ssl/fullchain.pem
	@sudo rm -f /etc/nginx/ssl/privkey.pem
	@sudo ln -sf /etc/letsencrypt/live/$(DOMAIN_NAME)/fullchain.pem /etc/nginx/ssl/fullchain.pem
	@sudo ln -sf /etc/letsencrypt/live/$(DOMAIN_NAME)/privkey.pem /etc/nginx/ssl/privkey.pem

	@$(call log_step,Reloading Nginx)
	@sudo systemctl reload nginx

	@$(call log_step,Verifying redirects)
	@./scripts/check_redirect.sh "http://$(DOMAIN_NAME)" "https://www.$(DOMAIN_NAME)" \
		|| ($(call log_error,Redirect failed: http://$(DOMAIN_NAME) → https://www.$(DOMAIN_NAME)) && exit 1)

	@./scripts/check_redirect.sh "http://www.$(DOMAIN_NAME)" "https://www.$(DOMAIN_NAME)" \
		|| ($(call log_error,Redirect failed: http://www.$(DOMAIN_NAME) → https://www.$(DOMAIN_NAME)) && exit 1)

	@./scripts/check_redirect.sh "https://$(DOMAIN_NAME)" "https://www.$(DOMAIN_NAME)" \
		|| ($(call log_error,Redirect failed: https://$(DOMAIN_NAME) → https://www.$(DOMAIN_NAME)) && exit 1)

	@$(call log_done,Nginx ready with SSL certificates)