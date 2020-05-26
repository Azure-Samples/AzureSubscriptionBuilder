#!/bin/bash
sudo apt-get -y update

# install LAMP Server (Apache, MySQL, and PHP)
sudo apt -y install lamp-server^

# Grant rights to /var/www
sudo chown -R $USER:$USER /var/www

# Get Subscription Builder Front End and Error page 
sudo wget wForm -O /var/www/html/index.html
sudo wget ePage -O /var/www/html/errorPage.html

# Restart Apache
sudo service apache2 restart