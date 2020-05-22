#!/bin/bash
sudo apt-get -y update

# install LAMP Server (Apache, MySQL, and PHP)
sudo apt -y install lamp-server^

# Write some html
sudo echo \<center\>\<h1\>My Demo App\</h1\>\<br/\>\</center\> > /var/www/html/demo.html

# Restart Apache
service apache2 restart 