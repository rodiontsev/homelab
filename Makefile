.PHONY: help validate-env \
	setup-docker \
	setup-ssh \
	setup-transmission start-transmission \
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

.DEFAULT_GOAL := help

# 1 - protocol name (HTTP or HTTPS)
# 2 - port number (80 or 443)
# 3 - iptables rule position (5 for HTTP, 6 for HTTPS)
define open_port
	@if ! ./scripts/check_port.sh "$(DOMAIN_NAME)" "$(2)"; then \
		echo "$(BLUE)• Configuring firewall for $(1)$(NC)"; \
		sudo iptables -I INPUT $(3) -m state --state NEW -p tcp --dport $(2) -j ACCEPT; \
		sudo iptables -L INPUT -v -n --line-numbers; \
		read -p "Save iptables configuration? [y/N] " confirm; \
		if [ "$$confirm" = "y" ] || [ "$$confirm" = "Y" ]; then \
			echo "$(BLUE)• Saving configuration$(NC)"; \
			sudo netfilter-persistent save; \
		else \
			echo "$(YELLOW)‼︎ Configuration not saved - will be lost on reboot$(NC)"; \
		fi; \
		if ! ./scripts/check_port.sh "$(DOMAIN_NAME)" "$(2)"; then \
			echo "$(RED)✗ Port $(2) still blocked - check cloud firewall$(NC)"; \
			exit 1; \
		fi; \
		echo "$(GREEN)✓ Port $(2) now accessible$(NC)"; \
	else \
		echo "$(GREEN)✓ Port $(2) already accessible$(NC)"; \
	fi
endef

define certbot
	sudo certbot certonly \
		$(if $(filter dry-run,$(1)),--dry-run,) \
		--webroot \
		--webroot-path /var/www/$(DOMAIN_NAME)/acme \
		--email $(LETS_ENCRYPT_EMAIL) \
		--domain $(DOMAIN_NAME) \
		--domain www.$(DOMAIN_NAME) \
		--deploy-hook "systemctl reload nginx" \
		--non-interactive \
		--agree-tos
endef

help:
	@echo "$(GREEN)Available targets:$(NC)"
	@echo "$(BLUE)  • setup-transmission$(NC)     - Set up Transmission"
	@echo "$(BLUE)  • start-transmission$(NC)     - Start Transmission"
	@echo "$(BLUE)  • setup-nginx$(NC)            - Set up Nginx with Let's Encrypt SSL"

validate-env:
	@echo "$(GREEN)Verifying environment...$(NC)"

	@echo "$(BLUE)• Verifying .env file$(NC)"
	@if [ ! -f .env ]; then \
		cp .env.example .env; \
		echo "$(YELLOW)‼︎ .env created from .env.example$(NC)"; \
		echo "  Review and update placeholder values before proceeding."; \
		exit 1; \
	fi

	@echo "$(BLUE)• Verifying environment variables$(NC)"
	@if [ "$(CURRENT_UID)" != "$(PUID)" ]; then \
		echo "$(YELLOW)‼︎ id -u ($(CURRENT_UID)) differs from PUID in .env ($(PUID))$(NC)"; \
		echo "  Mismatched uid/gid may cause volume permission errors"; \
		echo "  Update PUID/PGID in .env or re-run as the correct user"; \
		exit 1; \
	fi

	@echo "$(GREEN)✓ Environment ready$(NC)"

setup-docker:
	@echo "$(GREEN)Setting up Docker...$(NC)"
	@echo "$(BLUE)• [TODO]$(NC)"

setup-ssh:
	@echo "$(GREEN)Setting up SSH...$(NC)"
	@echo "$(BLUE)• [TODO]$(NC)"

setup-transmission: validate-env
	@echo "$(GREEN)Setting up Transmission...$(NC)"

	@echo "$(BLUE)• Creating mount points$(NC)"
	@sudo mkdir -p /mnt/downloads
	@sudo chown $(CURRENT_UID):$(CURRENT_GID) /mnt/downloads
	@sudo chmod 2775 /mnt/downloads

	@echo "$(BLUE)• Installing automount units$(NC)"
	@sudo cp configs/systemd/mnt-downloads.mount /etc/systemd/system/
	@sudo cp configs/systemd/mnt-downloads.automount /etc/systemd/system/
	@sudo systemctl daemon-reload

	@echo "$(BLUE)• Enabling automount$(NC)"
	@sudo systemctl enable --now mnt-downloads.automount

	@echo "$(BLUE)• Verifying automount status$(NC)"
	@systemctl status mnt-downloads.automount --no-pager

	@echo "$(BLUE)• Creating configuration files$(NC)"
	@mkdir -p $(APPDATA)/transmission
	@cp -r configs/transmission $(APPDATA)
	@find $(APPDATA)/transmission -name ".gitkeep" -delete
	@chmod -R 755 $(APPDATA)/transmission

	@echo "$(GREEN)✓ Transmission ready$(NC)"

start-transmission:
	@echo "$(GREEN)Starting Transmission...$(NC)"
	@docker compose --file docker-compose.yml up --detach --remove-orphans transmission
	@echo "$(GREEN)✓ Transmission started$(NC)"

help-nginx:
	@echo "$(YELLOW)⚠ Before proceeding:$(NC)"
	@echo "  • Ensure ports 80 and 443 are open in the cloud firewall"
	@echo "  • Verify DNS A/AAAA records point to this server"
	@echo ""
	@echo "$(BLUE)Cloud Provider Documentation:$(NC)"
	@echo "  • Oracle Cloud: https://docs.oracle.com/en-us/iaas/Content/developer/apache-on-ubuntu/01oci-ubuntu-apache-summary.htm#add-ingress-rules"
	@echo ""
	@read -p "Continue? [y/N] " confirm; \
	if [ "$$confirm" != "y" ] && [ "$$confirm" != "Y" ]; then \
		echo "$(RED)✗ Aborted$(NC)"; \
		exit 1; \
	fi

setup-nginx: help-nginx validate-env
	@echo "$(GREEN)Setting up Nginx with Let's Encrypt SSL...$(NC)"

	@test -x ./scripts/check_port.sh \
		|| (echo "$(RED)✗ Script not found or not executable: scripts/check_port.sh$(NC)" && exit 1)
	@test -x ./scripts/check_redirect.sh \
		|| (echo "$(RED)✗ Script not found or not executable: scripts/check_redirect.sh$(NC)" && exit 1)

	@echo "$(BLUE)• Installing Nginx and Certbot$(NC)"
	@sudo apt-get update && \
		sudo apt-get install --no-install-recommends -y \
			nginx=1.24\* \
			certbot=2.9\* \
			ssl-cert

	@echo "$(BLUE)• Verifying installations$(NC)"
	@systemctl status nginx --no-pager
	@certbot --version

	@echo "$(BLUE)• Creating web root and ACME directories$(NC)"
	@sudo mkdir -p /var/www/$(DOMAIN_NAME)/html
	@sudo mkdir -p /var/www/$(DOMAIN_NAME)/acme/.well-known/acme-challenge
	@echo "Hello, World!" | sudo tee /var/www/$(DOMAIN_NAME)/html/index.html > /dev/null

	@sudo chown -R $(CURRENT_UID):$(CURRENT_GID) /var/www/$(DOMAIN_NAME)/html
	@sudo chmod -R 755 /var/www/$(DOMAIN_NAME)

	@echo "$(BLUE)• Installing Nginx SSL configuration$(NC)"
	@sudo cp configs/nginx/snippets/security.conf /etc/nginx/snippets
	@sudo cp configs/nginx/snippets/ssl.conf /etc/nginx/snippets
	@sudo sed 's|example.com|$(DOMAIN_NAME)|g' configs/nginx/sites-available/example.com \
		| sudo tee /etc/nginx/sites-available/$(DOMAIN_NAME) > /dev/null

	@echo "$(BLUE)• Creating temporary self-signed certificates$(NC)"
	@sudo mkdir -p /etc/nginx/ssl
	@sudo ln -sf /etc/ssl/certs/ssl-cert-snakeoil.pem /etc/nginx/ssl/fullchain.pem
	@sudo ln -sf /etc/ssl/private/ssl-cert-snakeoil.key /etc/nginx/ssl/privkey.pem

	@echo "$(BLUE)• Creating Diffie-Hellman parameters file$(NC)"
	@read -p "Use pre-generated DH parameters? (faster, generates new if no) [y/N] " confirm; \
	if [ "$$confirm" = "y" ] || [ "$$confirm" = "Y" ]; then \
        echo "$(BLUE)• Using pre-generated DH parameters$(NC)"; \
		sudo cp configs/nginx/ssl/dhparams.pem /etc/nginx/ssl; \
	else \
        echo "$(BLUE)• Generating new DH parameters (this may take several minutes)$(NC)"; \
		sudo openssl dhparam -out /etc/nginx/ssl/dhparams.pem 4096; \
	fi

	@echo "$(BLUE)• Disabling default site$(NC)"
	@sudo rm -f /etc/nginx/sites-enabled/default

	@echo "$(BLUE)• Enabling $(DOMAIN_NAME)$(NC)"
	@sudo ln -sf /etc/nginx/sites-available/$(DOMAIN_NAME) /etc/nginx/sites-enabled/

	@echo "$(BLUE)• Testing Nginx configuration$(NC)"
	@sudo nginx -t || (echo "$(RED)✗ Nginx configuration test failed$(NC)" && exit 1)

	@echo "$(BLUE)• Restarting Nginx$(NC)"
	@sudo systemctl restart nginx

	@echo "$(BLUE)• Configuring firewall for HTTP and HTTPS$(NC)"
	$(call open_port,HTTP,80,5)
	$(call open_port,HTTPS,443,6)

	@echo "$(BLUE)• Testing Let's Encrypt configuration (dry run)$(NC)"
	@$(call certbot,dry-run)

	@echo "$(BLUE)• Obtaining Let's Encrypt certificates$(NC)"
	@$(call certbot)

	@echo "$(BLUE)• Replacing self-signed certificates with Let's Encrypt certificates$(NC)"
	@sudo rm -f /etc/nginx/ssl/fullchain.pem
	@sudo rm -f /etc/nginx/ssl/privkey.pem
	@sudo ln -sf /etc/letsencrypt/live/$(DOMAIN_NAME)/fullchain.pem /etc/nginx/ssl/fullchain.pem
	@sudo ln -sf /etc/letsencrypt/live/$(DOMAIN_NAME)/privkey.pem /etc/nginx/ssl/privkey.pem

	@echo "$(BLUE)• Reloading Nginx$(NC)"
	@sudo systemctl reload nginx

	@echo "$(BLUE)• Verifying redirects$(NC)"
	@./scripts/check_redirect.sh "http://$(DOMAIN_NAME)" "https://www.$(DOMAIN_NAME)" \
		|| (echo "$(RED)✗ Redirect failed: http://$(DOMAIN_NAME) → https://www.$(DOMAIN_NAME)$(NC)" && exit 1)

	@./scripts/check_redirect.sh "http://www.$(DOMAIN_NAME)" "https://www.$(DOMAIN_NAME)" \
		|| (echo "$(RED)✗ Redirect failed: http://www.$(DOMAIN_NAME) → https://www.$(DOMAIN_NAME)$(NC)" && exit 1)

	@./scripts/check_redirect.sh "https://$(DOMAIN_NAME)" "https://www.$(DOMAIN_NAME)" \
		|| (echo "$(RED)✗ Redirect failed: https://$(DOMAIN_NAME) → https://www.$(DOMAIN_NAME)$(NC)" && exit 1)

	@echo "$(GREEN)✓ Nginx ready with SSL certificates$(NC)"
