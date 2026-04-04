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

help:
	@echo "$(GREEN)Available targets:$(NC)"
	@echo "$(BLUE)• setup-transmission$(NC)     - Set up Transmission"
	@echo "$(BLUE)• start-transmission$(NC)     - Start Transmission"
	@echo "$(BLUE)• setup-nginx$(NC)            - Set up Nginx with Let's Encrypt Certificates"

validate-env:
	@echo "$(GREEN)Verifying environment...(NC)"

	@echo "$(BLUE)• Verifying .env file$(NC)"
	@if [ ! -f .env ]; then \
		cp .env.example .env; \
		echo "$(YELLOW)WARN: .env is created from .env.example"; \
		echo "      Review and update the placeholder values before proceeding$(NC)"; \
		exit 1; \
	fi

	@echo "$(BLUE)• Verifying environment variables$(NC)"
	@if [ "$(CURRENT_UID)" != "$(PUID)" ]; then \
		echo "$(YELLOW)WARN: id -u ($(CURRENT_UID)) differs from PUID in .env ($(PUID))$(NC)"; \
		echo "      Mismatched uid/gid may cause volume permission errors."; \
		echo "      Update PUID/PGID in .env or re-run as the correct user."; \
		exit 1; \
	fi

	@echo "$(GREEN)✓ Environment ready$(NC)"

setup-docker:
	@echo "$(GREEN)Setting up Docker...$(NC)"
	@echo "$(BLUE)• [TODO]]$(NC)"

setup-ssh:
	@echo "$(GREEN)Setting up SSH...$(NC)"
	@echo "$(BLUE)• [TODO]]$(NC)"

setup-transmission: validate-env
	@echo "$(GREEN)Setting up Transmission...(NC)"

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
	@echo "$(GREEN)Starting Transmission...(NC)"
	@docker compose --file docker-compose.yml up --detach --remove-orphans transmission

help-nginx:
	@echo "$(YELLOW)WARN: Before processing:$(NC)"
	@echo "• Ensure ports 80 and 443 are open in the cloud firewall"
	@echo "• Verify DNS A/AAAA records point to this server"
	@echo ""
	@echo "$(BLUE)Cloud Provider Documentation:$(NC)"
	@echo "• Oracle Cloud: https://docs.oracle.com/en-us/iaas/Content/developer/apache-on-ubuntu/01oci-ubuntu-apache-summary.htm#add-ingress-rules"
	@echo ""
	@read -p "Continue? [y/N] " confirm; \
	if [ "$$confirm" != "y" ] && [ "$$confirm" != "Y" ]; then \
		echo "$(RED)Aborted$(NC)"; \
		exit 1; \
	fi

setup-nginx: help-nginx validate-env
	@echo "$(GREEN)Setting up Nginx with Let's Encrypt Certificates...$(NC)"

	@echo "$(BLUE)• Installing Nginx and Certbot$(NC)"
	@sudo apt-get update && \
		sudo apt-get install --no-install-recommends -y \
			nginx=1.24\* \
			certbot=2.9\* \
			python3-certbot-nginx=2.9\* \
			ssl-cert

	@echo "$(BLUE)• Verifying installations$(NC)"
	@systemctl status nginx --no-pager
	@certbot --version

	@echo "$(BLUE)• Creating web root and certbot directories$(NC)"
	@sudo mkdir -p /var/www/$(DOMAIN_NAME)/html
	@sudo mkdir -p /var/www/$(DOMAIN_NAME)/certbot/.well-known/acme-challenge

	@echo "Hello, World!" \
		| sudo tee /var/www/$(DOMAIN_NAME)/html/index.html > /dev/null

	@sudo chown -R $(CURRENT_UID):$(CURRENT_GID) /var/www/$(DOMAIN_NAME)/html
	@sudo chmod -R 755 /var/www/$(DOMAIN_NAME)

	@echo "$(BLUE)• Installing Nginx SSL configuration$(NC)"
	@sudo cp configs/nginx/snippets/security.conf /etc/nginx/snippets
	@sudo sed 's|example.com|$(DOMAIN_NAME)|g' configs/nginx/sites-available/example.com \
		| sudo tee /etc/nginx/sites-available/$(DOMAIN_NAME) > /dev/null

	@echo "$(BLUE)• Creating temporary self-signed certificates$(NC)"
	@sudo mkdir -p /etc/letsencrypt/live/$(DOMAIN_NAME)
	@sudo cp /etc/ssl/certs/ssl-cert-snakeoil.pem /etc/letsencrypt/live/$(DOMAIN_NAME)/fullchain.pem
	@sudo cp /etc/ssl/private/ssl-cert-snakeoil.key /etc/letsencrypt/live/$(DOMAIN_NAME)/privkey.pem

	@echo "$(BLUE)• Downloading Certbot configuration$(NC)"
	@sudo curl -sL "https://raw.githubusercontent.com/certbot/certbot/refs/tags/v5.4.0/certbot-nginx/src/certbot_nginx/_internal/tls_configs/options-ssl-nginx.conf" \
		-o /etc/letsencrypt/options-ssl-nginx.conf

	@sudo curl -sL "https://raw.githubusercontent.com/certbot/certbot/refs/tags/v5.4.0/certbot/src/certbot/ssl-dhparams.pem" \
		-o /etc/letsencrypt/ssl-dhparams.pem

	@echo "$(BLUE)• Disabling default site$(NC)"
	@sudo rm -f /etc/nginx/sites-enabled/default

	@echo "$(BLUE)• Enabling $(DOMAIN_NAME)$(NC)"
	@sudo ln -sf /etc/nginx/sites-available/$(DOMAIN_NAME) /etc/nginx/sites-enabled/

	@echo "$(BLUE)• Testing Nginx configuration$(NC)"
	@sudo nginx -t || (echo "$(RED)✗ Nginx configuration test failed$(NC)" && exit 1)

	@echo "$(BLUE)• Testing Let's Encrypt configuration (dry run)$(NC)"
	@sudo certbot certonly \
		--dry-run \
		--webroot \
		--webroot-path /var/www/$(DOMAIN_NAME)/certbot \
		--domain $(DOMAIN_NAME) \
		--domain www.$(DOMAIN_NAME)

	@echo "$(BLUE)• Obtaining Let's Encrypt certificates$(NC)"
	@sudo certbot -n --agree-tos \
		--email $(LETS_ENCRYPT_EMAIL) \
		--webroot \
		--webroot-path /var/www/$(DOMAIN_NAME)/certbot \
		--deploy-hook "systemctl reload nginx" \
		--domain $(DOMAIN_NAME) \
		--domain www.$(DOMAIN_NAME)

	@echo "$(BLUE)• Restarting Nginx$(NC)"
	@sudo systemctl restart nginx

	@echo "$(BLUE)• Configuring firewall for HTTP and HTTPS$(NC)"	
	@if ./scripts/check_port.sh "$(DOMAIN_NAME)" "80"; then \
		echo "$(GREEN)✓ Firewall for HTTP already configured$(NC)"; \
	else \
		echo "$(BLUE)• Configuring firewall for HTTP$(NC)"; \
		sudo iptables -I INPUT 5 -m state --state NEW -p tcp --dport 80 -j ACCEPT; \
		sudo iptables -L INPUT -v -n --line-numbers; \

		read -p "Press Enter to save HTTP configuration or Ctrl+C to abort..."
		sudo netfilter-persistent save; \
	fi

	@if ./scripts/check_port.sh "$(DOMAIN_NAME)" "443"; then \
		echo "$(GREEN)✓ Firewall for HTTPS already configured$(NC)"; \
	else \
		echo "$(BLUE)• Configuring firewall for HTTPS$(NC)"; \
		sudo iptables -I INPUT 6 -m state --state NEW -p tcp --dport 443 -j ACCEPT
		sudo iptables -L INPUT -v -n --line-numbers

		read -p "Press Enter to save HTTPS configuration or Ctrl+C to abort..."
		sudo netfilter-persistent save
	fi

	@echo "$(BLUE)• Verifying redirects$(NC)"	
	@./scripts/check_redirect.sh "http://$(DOMAIN_NAME)" "https://www.$(DOMAIN_NAME)" \
		|| (echo "$(RED)✗ Redirect failed: http://$(DOMAIN_NAME) → https://www.$(DOMAIN_NAME)$(NC)" && exit 1)

	@./scripts/check_redirect.sh "http://www.$(DOMAIN_NAME)" "https://www.$(DOMAIN_NAME)" \
		|| (echo "$(RED)✗ Redirect failed: http://www.$(DOMAIN_NAME) → https://www.$(DOMAIN_NAME)$(NC)" && exit 1)

	@./scripts/check_redirect.sh "https://$(DOMAIN_NAME)" "https://www.$(DOMAIN_NAME)" \
		|| (echo "$(RED)✗ Redirect failed: https://$(DOMAIN_NAME) → https://www.$(DOMAIN_NAME)$(NC)" && exit 1)

	@echo "$(GREEN)✓ Nginx ready with SSL certificates$(NC)"
