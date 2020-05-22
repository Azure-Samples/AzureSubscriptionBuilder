#!/bin/bash
sudo apt-get -y update

# install LAMP Server (Apache, MySQL, and PHP)
sudo apt -y install lamp-server^

# Grant rights to /var/www
sudo chown -R $USER:$USER /var/www

# Get Subscription Builder Front End and Error page 
sudo wget https://bootstrapstgacct.blob.core.windows.net/webserver/webForm.html -O /var/www/html/index.html
sudo wget https://bootstrapstgacct.blob.core.windows.net/webserver/errorPage.html -O /var/www/html/errorPage.html

# Restart Apache
sudo service apache2 restart 