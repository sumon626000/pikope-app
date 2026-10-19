# Image for the API (Apache + mod_php), the WebSocket server and the cleanup job.
FROM php:8.4-apache

RUN docker-php-ext-install pdo_mysql pcntl \
 && a2enmod rewrite headers remoteip \
 && { \
      echo 'upload_max_filesize = 3M'; \
      echo 'post_max_size = 4M'; \
      echo 'expose_php = Off'; \
      echo 'display_errors = Off'; \
      echo 'log_errors = On'; \
    } > /usr/local/etc/php/conf.d/app.ini

COPY deploy/docker/apache.conf /etc/apache2/sites-available/000-default.conf
COPY . /var/www/app
RUN rm -rf /var/www/app/deploy/docker /var/www/app/tests /var/www/app/dist \
 && touch /var/www/app/.env \
 && mkdir -p /var/www/app/public/uploads/avatars \
 && chown -R www-data:www-data /var/www/app/public/uploads

WORKDIR /var/www/app
