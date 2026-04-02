FROM nginx:alpine

COPY index.html /usr/share/nginx/html/index.html
COPY js/ /usr/share/nginx/html/js/
COPY css/ /usr/share/nginx/html/css/

# Health endpoint via nginx
RUN echo 'server { listen 80; location /health { return 200 "OK"; add_header Content-Type text/plain; } location / { root /usr/share/nginx/html; index index.html; try_files $uri $uri/ /index.html; } }' > /etc/nginx/conf.d/default.conf

EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
