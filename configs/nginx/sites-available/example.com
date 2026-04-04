# Reject requests to server IP directly
server {
    listen 80 default_server;
    listen 443 ssl http2 default_server;
    server_name _;

    # Self-signed certificate for default server (don't expose real domain)
    include snippets/snakeoil.conf;

    return 444;  # Close connection without response
}

server {
    listen 80;
    server_name example.com www.example.com;

    include snippets/security.conf;

    # Allow Let's Encrypt challenges
    location ^~ /.well-known/acme-challenge/ {
        # Dedicated directory for challenges
        root /var/www/example.com/certbot;
        try_files $uri =404;
    }

    # Redirect all other HTTP traffic to HTTPS www
    location / {
        return 301 https://www.example.com$request_uri;
    }
}

# Redirect naked domain to www
server {
    listen 443 ssl http2;
    server_name example.com;

    include snippets/security.conf;

    ssl_certificate /etc/letsencrypt/live/example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/example.com/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

    # Redirect to www
    return 301 https://www.example.com$request_uri;
}

server {
    listen 443 ssl http2;

    server_name www.example.com;

    include snippets/security.conf;

    root /var/www/example.com/html;
    index index.html;

    ssl_certificate /etc/letsencrypt/live/example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/example.com/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

    location / {
        try_files $uri $uri/ =404;
    }
}