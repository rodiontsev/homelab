# Reject requests to server IP directly
server {
    listen 80 default_server;
    server_name _;

    return 444;  # Close connection without response
}

# Redirect naked domain to www
server {
    listen 80;
    server_name example.com;

    include snippets/security.conf;

    # Redirect to www
    return 301 http://www.example.com$request_uri;
}

server {
    listen 80;
    server_name www.example.com;

    include snippets/security.conf;

    root /var/www/example.com/html;
    index index.html;

    location / {
        try_files $uri $uri/ =404;
    }
}