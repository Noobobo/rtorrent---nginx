#!/bin/bash
#
# Script d'installation ruTorrent / Nginx v 1.3
# Auteur : Ex_Rat
#
# Nécessite Debian 7.x - 32/64 bits minimum & un serveur fraîchement installé
#
# Multi-utilisateurs
# Inclus VsFTPd (ftp & ftps sur le port 21), Fail2ban (avec conf nginx, ftp & ssh) & Proxy php
# Seedbox-Manager, Auteurs: Magicalex, Hydrog3n et Backtoback
#
# Tiré du tutoriel de Magicalex pour lufki.org disponible ici:
# http://mondedie.fr/viewtopic.php?id=5302
# Aide, support & plus si affinités à la même adresse ! http://mondedie.fr/
#
# Merci Aliochka & Meister pour les conf de munin et VsFTPd
# à Albaret pour le coup de main sur# la gestion d'users et
# Jedediah pour avoir joué avec le html/css du thème
#
# Installation:
#
# apt-get update && apt-get upgrade -y
# apt-get install git-core -y
#
# cd /tmp
# git clone https://github.com/Noobobo/rtorrent---nginx.git
 # mv rtorrent---nginx install-rutorrent
# cd install-rutorrent
# chmod a+x rtorrent---nginx.sh && ./rtorrent---nginx.sh
#
# Pour gérer vos utilisateurs ultérieurement, il vous suffit de relancer le script
## Inspiration:
# hexodark https://github.com/gaaara/


# variables couleurs
CSI="\033["
CEND="${CSI}0m"
CRED="${CSI}1;31m"
CGREEN="${CSI}1;32m"
CYELLOW="${CSI}1;33m"
CBLUE="${CSI}1;34m"

clear

# contrôle droits utilisateur
if [ $(id -u) -ne 0 ]; then
	echo ""
	echo -e "${CRED}                      Ce script doit être exécuté en root.$CEND" 1>&2
	echo ""
	exit 1
fi

# Contrôle installation
if [ ! -f /etc/nginx/sites-enabled/rutorrent.conf ]; then

####################################
# lancement installation ruTorrent #
####################################

# message d'accueil
echo ""
echo -e "${CBLUE}          Bienvenue dans cette installation automatique de ruTorrent$CEND"
echo ""

# logo
echo -e "${CBLUE}
                                      |          |_)         _|     
            __ \`__ \   _ \  __ \   _\` |  _ \  _\` | |  _ \   |    __|
            |   |   | (   | |   | (   |  __/ (   | |  __/   __| |   
           _|  _|  _|\___/ _|  _|\__,_|\___|\__,_|_|\___|_)_|  _|   

$CEND"
echo ""
echo -e "${CYELLOW}        Le premier utilisateur sera l'administrateur de Seedbox-Manager,$CEND"
echo -e "${CYELLOW}     vous pourrez ajouter d'autres utilisateurs à la fin de l'installation.$CEND"
echo ""

# demande nom et mot de passe
echo -e "${CGREEN}Entrez le nom du premier utilisateur (en minuscule): $CEND"
read USER
echo ""
echo -e "${CGREEN}Entrez le mot de passe pour cet utilisateur,\nou appuyez sur \"$CEND${CYELLOW}Entrée$CEND${CGREEN}\" pour en générer un automatiquement: $CEND"
read REPPWD
if [ "$REPPWD" = "" ]; then
    while :; do
    AUTOPWD=$(strings /dev/urandom | grep -o '[1-9A-NP-Za-np-z]' | head -n 8 | tr -d '\n')
    echo -e -n "${CGREEN}Voulez vous utiliser$CEND ${CYELLOW}$AUTOPWD$CEND${CGREEN} comme mot de passe ? (y/n] : $CEND"
        read REPONSEPWD
        if [ "$REPONSEPWD" = "n" ]; then
            echo
        else
           PWD=$AUTOPWD
           break

       fi
    done
else
    PWD=$REPPWD
fi
echo ""

PORT=5001

# email admin seedbox-Manager
echo -e "${CGREEN}Entrez l'email de contact qui apparaîtra dans Seedbox-Manager: $CEND"
read INSTALLMAIL
IFS="@"
set -- $INSTALLMAIL
if [ "${#@}" -ne 2 ];then
    EMAIL=wtf@lufki.org
else
    EMAIL=$INSTALLMAIL
fi

# installation vsftpd
echo ""
echo -n -e "${CGREEN}Voulez vous installer un serveur FTP (y/n): $CEND"
read SERVFTP
echo ""

# récupération 5% root sur /home ou /home/user si présent
FS=$(df -h | grep /home/$USER | cut -c 6-9)

if [ "$FS" = "" ]; then
    FS=$(df -h | grep /home | cut -c 6-9)
	if [ "$FS" = "" ]; then
		echo
	else
        tune2fs -m 0 /dev/$FS
        mount -o remount /home
	fi
else
    tune2fs -m 0 /dev/$FS
    mount -o remount /home/$USER
fi

# variable passe nginx
PASSNGINX=${PWD}
echo ""

# ajout utilisateur
useradd -M -s /bin/bash "$USER"

# création du mot de passe utilisateur
echo "${USER}:${PWD}" | chpasswd

# anti-bug /home/user déjà existant
mkdir -p /home/$USER
chown -R $USER:$USER /home/$USER

# variable utilisateur majuscule
USERMAJ=`echo $USER | tr "[:lower:]" "[:upper:]"`

# récupération IP serveur
IP=$(ifconfig | grep 'inet addr:' | grep -v inet6 | grep -vE '127\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | cut -d: -f2 | awk '{ print $1}' | head -1)
if [ "$IP" = "" ]; then
	IP=$(wget -qO- ipv4.icanhazip.com)
fi

# gestionnaire de paquet
if [ "`dpkg --status aptitude | grep Status:`" == "Status: install ok installed" ]
	then
		packetg="aptitude"
	else
		packetg="apt-get"
fi

# log de l'installation
exec 2>/tmp/install.log

# modification DNS
rm /etc/resolv.conf && touch /etc/resolv.conf
cat <<'EOF' >  /etc/resolv.conf
nameserver 127.0.0.1
nameserver 208.67.220.220
nameserver 208.67.222.222
EOF

# ajout des dépots non-free
echo "#dépôt paquet propriétaire
deb http://ftp2.fr.debian.org/debian/ wheezy main non-free
deb-src http://ftp2.fr.debian.org/debian/ wheezy main non-free

# dépôt dotdeb php 5.5
deb http://packages.dotdeb.org wheezy-php55 all
deb-src http://packages.dotdeb.org wheezy-php55 all

# dépôt nginx
deb http://nginx.org/packages/debian/ wheezy nginx
deb-src http://nginx.org/packages/debian/ wheezy nginx ">> /etc/apt/sources.list

# ajout des clés

# dotdeb
cd /tmp
wget http://www.dotdeb.org/dotdeb.gpg
apt-key add dotdeb.gpg

# nginx
cd /tmp
wget http://nginx.org/keys/nginx_signing.key
apt-key add nginx_signing.key
echo ""
echo -e "${CBLUE}Mise à jour des dépôts$CEND     ${CGREEN}Done !$CEND"
echo ""

# installation des paquets
$packetg update
$packetg safe-upgrade -y
echo ""
echo -e "${CBLUE}Mise à jour du serveur$CEND     ${CGREEN}Done !$CEND"
echo ""

$packetg install -y htop openssl python build-essential libssl-dev pkg-config whois libcurl4-openssl-dev libsigc++-2.0-dev libncurses5-dev nginx vim nano ccze screen subversion apache2-utils curl php5 php5-cli php5-fpm php5-curl php5-geoip git unrar rar zip ffmpeg buildtorrent mediainfo fail2ban ntp ntpdate munin
echo ""
echo -e "${CBLUE}Installation des paquets essentiels$CEND     ${CGREEN}Done !$CEND"
echo ""

# téléchargement complément favicon
cd /tmp
wget http://www.bonobox.net/script/favicon.tar.gz
tar xzfv favicon.tar.gz

# création fichiers couleurs nano
cat <<'EOF' >  /usr/share/nano/ini.nanorc
## ini highlighting
syntax "ini" "\.ini(\.old|~)?$"
color brightred "=.*$"
color green "="
color brightblue "-?[0-9\.]+\s*($|;)"
color brightmagenta "ON|OFF|On|Off|on|off\s*($|;)"
color brightcyan "^\s*\[.*\]"
color cyan "^\s*[a-zA-Z0-9_\.]+"
color brightyellow ";.*$"
EOF

cat <<'EOF' >  /usr/share/nano/conf.nanorc
## Generic *.conf file syntax highlighting
syntax "conf" "\.(c(onf|nf|fg))$"
icolor yellow ""(\\.|[^"])*""
icolor brightyellow start="=" end="$"
icolor magenta start="(^|[[:space:]])[0-9a-z-]" end="="
icolor brightred "(^|[[:space:]])((\[|\()[0-9a-z_!@#$%^&*-]+(\]|\)))"
color green "[[:space:]][0-9.KM]+"
color cyan start="(^|[[:space:]])(#|;).*$" end="$"
color brightblue "(^|[[:space:]])(#|;)"
EOF

cat <<'EOF' >  /usr/share/nano/xorg.nanorc
## syntax highlighting in xorg.conf
##
syntax "xorg" "xorg\.conf$"
color brightwhite "(Section|EndSection|Sub[sS]ection|EndSub[sS]ection)"
# keywords
color yellow "[^A-Za-z0-9](Identifier|Screen|InputDevice|Option|RightOf|LeftOf|Driver|RgbPath|FontPath|ModulePath|Load|VendorName|ModelName|BoardName|BusID|Device|Monitor|DefaultDepth|View[pP]ort|Depth|Virtual|Modes|Mode|DefaultColorDepth|Modeline|\+vsync|\+hsync|HorizSync|VertRefresh)[^A-Za-z0-9]"
# numbers
color magenta "[0-9]"
# strings
color green ""(\\.|[^\"])*""
# comments
color blue "#.*"
EOF

# édition conf nano
echo "
## Config Files (.ini)
include \"/usr/share/nano/ini.nanorc\"

## Config Files (.conf)
include \"/usr/share/nano/conf.nanorc\"

## Xorg.conf
include \"/usr/share/nano/xorg.nanorc\"">> /etc/nanorc

echo ""
echo -e "${CBLUE}Configuration couleurs Nano$CEND     ${CGREEN}Done !$CEND"
echo ""

# Config ntp & réglage heure fr
echo "Europe/Paris" > /etc/timezone
cp /usr/share/zoneinfo/Europe/Paris /etc/localtime

sed -i "s/server 0/#server 0/g;" /etc/ntp.conf
sed -i "s/server 1/#server 1/g;" /etc/ntp.conf
sed -i "s/server 2/#server 2/g;" /etc/ntp.conf
sed -i "s/server 3/#server 3/g;" /etc/ntp.conf

echo "
server 0.fr.pool.ntp.org
server 1.fr.pool.ntp.org
server 2.fr.pool.ntp.org
server 3.fr.pool.ntp.org">> /etc/ntp.conf

ntpdate 0.fr.pool.ntp.org

# installation XMLRPC LibTorrent rTorrent
cd /tmp
svn checkout http://svn.code.sf.net/p/xmlrpc-c/code/stable xmlrpc-c
cd xmlrpc-c
./configure --disable-cplusplus
make
make install
cd ..
rm -rv xmlrpc-c
echo ""
echo -e "${CBLUE}Installation XMLRPC$CEND     ${CGREEN}Done !$CEND"
echo ""

# clone rTorrent et libTorrent
wget --no-check-certificate http://libtorrent.rakshasa.no/downloads/libtorrent-0.13.4.tar.gz
tar -xf libtorrent-0.13.4.tar.gz

wget --no-check-certificate http://libtorrent.rakshasa.no/downloads/rtorrent-0.9.4.tar.gz
tar -xzf rtorrent-0.9.4.tar.gz

# libTorrent compilation
cd libtorrent-0.13.4
./autogen.sh
./configure
make
make install
echo ""
echo -e "${CBLUE}Installation libTorrent$CEND     ${CGREEN}Done !$CEND"
echo ""

# rTorrent compilation
cd ../rtorrent-0.9.4
./autogen.sh
./configure --with-xmlrpc-c
make
make install
echo ""
echo -e "${CBLUE}Installation rTorrent$CEND     ${CGREEN}Done !$CEND"
echo ""

# création des dossiers
su $USER -c 'mkdir -p ~/watch ~/torrents ~/.session '

# création dossier scripts perso
mkdir /usr/share/scripts-perso

# création accueil serveur
mkdir -p /var/www
cp -R /tmp/install-rutorrent/base /var/www/base

# déplacement proxy
cp -R /tmp/install-rutorrent/proxy /var/www/proxy

# téléchargement et déplacement de rutorrent
svn checkout http://rutorrent.googlecode.com/svn/trunk/rutorrent/
svn checkout http://rutorrent.googlecode.com/svn/trunk/plugins/
mv ./plugins/* ./rutorrent/plugins/
rm -R ./plugins
mv rutorrent/ /var/www
echo ""
echo -e "${CBLUE}Installation ruTorrent$CEND     ${CGREEN}Done !$CEND"
echo ""

# installation des Plugins
cd /var/www/rutorrent/plugins/

# logoff
svn co http://rutorrent-logoff.googlecode.com/svn/trunk/ logoff

# chat
svn co http://rutorrent-chat.googlecode.com/svn/trunk/ chat

# tadd-labels
wget http://rutorrent-tadd-labels.googlecode.com/files/lbll-suite_0.8.1.tar.gz
tar zxfv lbll-suite_0.8.1.tar.gz
rm lbll-suite_0.8.1.tar.gz

# goto
cp -R /tmp/install-rutorrent/plugins/goto /var/www/rutorrent/plugins/goto
sed -i "s/@IP@/$IP/g;" /var/www/rutorrent/plugins/goto/init.js

# nfo
cp -R /tmp/install-rutorrent/plugins/nfo /var/www/rutorrent/plugins/nfo

# filemanager
svn co http://svn.rutorrent.org/svn/filemanager/trunk/filemanager

# filemanager config
cat <<'EOF' >  /var/www/rutorrent/plugins/filemanager/conf.php
<?php
$fm['tempdir'] = '/tmp';		// path were to store temporary data ; must be writable
$fm['mkdperm'] = 755;			// default permission to set to new created directories

// set with fullpath to binary or leave empty
$pathToExternals['rar'] = '/usr/bin/rar';
$pathToExternals['zip'] = '/usr/bin/zip';
$pathToExternals['unzip'] = '/usr/bin/unzip';
$pathToExternals['tar'] = '/bin/tar';
$pathToExternals['gzip'] = '/bin/gzip';
$pathToExternals['bzip2'] = '/bin/bzip2';

// archive mangling, see archiver man page before editing

$fm['archive']['types'] = array('rar', 'zip', 'tar', 'gzip', 'bzip2');




$fm['archive']['compress'][0] = range(0, 5);
$fm['archive']['compress'][1] = array('-0', '-1', '-9');
$fm['archive']['compress'][2] = $fm['archive']['compress'][3] = $fm['archive']['compress'][4] = array(0);

?>
EOF

# fileupload
svn co http://svn.rutorrent.org/svn/filemanager/trunk/fileupload
chmod 775 fileupload/scripts/upload

# dépendance

# plowshare
cd /home
git clone https://code.google.com/p/plowshare/ plowshare4
cd plowshare4
make install

# configuration du plugin create
sed -i "s#$useExternal = false;#$useExternal = 'buildtorrent';#" /var/www/rutorrent/plugins/create/conf.php
sed -i "s#$pathToCreatetorrent = '';#$pathToCreatetorrent = '/usr/bin/buildtorrent';#" /var/www/rutorrent/plugins/create/conf.php

# fileshare
cd /var/www/rutorrent/plugins/
svn co http://svn.rutorrent.org/svn/filemanager/trunk/fileshare
chown -R www-data:www-data /var/www/rutorrent/plugins/fileshare
ln -s /var/www/rutorrent/plugins/fileshare/share.php /var/www/base/share.php

# configuration share.php
cat <<'EOF' >  /var/www/rutorrent/plugins/fileshare/conf.php
<?php

// limits
// 0 = unlimited
$limits['duration'] = 200;		// maximum duration hours
$limits['links'] = 0;			//maximum sharing links per user

// path on domain where a symlink to share.php can be found
// example: http://mydomain.com/share.php
$downloadpath = 'http://@IP@/share.php';

?>
EOF
sed -i "s/@IP@/$IP/g;" /var/www/rutorrent/plugins/fileshare/conf.php

# script mise à jour mensuel geoip et complément plugin city
# création dossier par sécurité suite bug d'install
mkdir /usr/share/GeoIP

# variable minutes aléatoire crontab geoip
MAXIMUM=58
MINIMUM=1
UPGEOIP=$((MINIMUM+RANDOM*(1+MAXIMUM-MINIMUM)/32767))

cd /usr/share/scripts-perso/

cat <<'EOF' >  /usr/share/scripts-perso/updateGeoIP.sh
#!/bin/bash
#
# mise à jour mensuel db geoip et complément plugin city
cd /tmp
wget http://geolite.maxmind.com/download/geoip/database/GeoLiteCountry/GeoIP.dat.gz
wget http://geolite.maxmind.com/download/geoip/database/GeoIPv6.dat.gz
wget http://geolite.maxmind.com/download/geoip/database/GeoLiteCity.dat.gz
/bin/gunzip GeoIP.dat.gz GeoIPv6.dat.gz GeoLiteCity.dat.gz
cp -f GeoLiteCity.dat /usr/share/GeoIP/GeoIPCity.dat
cp -f GeoLiteCity.dat /usr/share/GeoIP/GeoLiteCity.dat
cp -f GeoIP.dat /usr/share/GeoIP/GeoIP.dat
cp -f GeoIPv6.dat /usr/share/GeoIP/GeoIPv6.dat
rm GeoIP.dat GeoIPv6.dat GeoLiteCity.dat
EOF

chmod a+x updateGeoIP.sh
sh updateGeoIP.sh

# favicons trackers
cp /tmp/favicon/*.png /var/www/rutorrent/plugins/tracklabels/trackers/

# ratiocolor
cp -R /tmp/install-rutorrent/plugins/ratiocolor /var/www/rutorrent/plugins/ratiocolor

# pausewebui
cp -R /tmp/install-rutorrent/plugins/pausewebui /var/www/rutorrent/plugins/pausewebui

# plugin seedbox-manager
cd /var/www/rutorrent/plugins
git clone https://github.com/Hydrog3n/linkseedboxmanager.git
sed -i "s/http:\/\/seedbox-manager.ndd.tld/https:\/\/$IP\/seedbox-manager\//g;" /var/www/rutorrent/plugins/linkseedboxmanager/conf.php

# configuration logoff
sed -i "s/scars,user1,user2/$USER/g;" /var/www/rutorrent/plugins/logoff/conf.php

# ajout thèmes
rm -r /var/www/rutorrent/plugins/theme/themes/Blue
cp -R /tmp/install-rutorrent/theme/ru/Blue /var/www/rutorrent/plugins/theme/themes/Blue
cp -R /tmp/install-rutorrent/theme/ru/SpiritOfBonobo /var/www/rutorrent/plugins/theme/themes/SpiritOfBonobo

# configuration theme
sed -i "s/defaultTheme = \"\"/defaultTheme = \"SpiritOfBonobo\"/g;" /var/www/rutorrent/plugins/theme/conf.php

echo ""
echo -e "${CBLUE}Installation des plugins$CEND     ${CGREEN}Done !$CEND"
echo ""

# curl config
sed -i "s/\"curl\"[[:blank:] [:blank:] ]=> '',/\"curl\"  => '\/usr\/bin\/curl',/g;" /var/www/rutorrent/conf/config.php
sed -i "s/\"stat\"[[:blank:] [:blank:] ]=> '',/\"stat\"  => '\/usr\/bin\/stat',/g;" /var/www/rutorrent/conf/config.php

# liens symboliques et permissions
ldconfig
chown -R www-data:www-data /var/www/rutorrent
chown -R www-data:www-data /var/www/base
chown -R www-data:www-data /var/www/proxy

# php
sed -i "s/2M/10M/g;" /etc/php5/fpm/php.ini
sed -i "s/8M/10M/g;" /etc/php5/fpm/php.ini
sed -i "s/expose_php = On/expose_php = Off/g;" /etc/php5/fpm/php.ini
sed -i "s/^;date.timezone =/date.timezone = Europe\/Paris/g;" /etc/php5/fpm/php.ini

sed -i "s/^;listen.owner = www-data/listen.owner = www-data/g;" /etc/php5/fpm/pool.d/www.conf
sed -i "s/^;listen.group = www-data/listen.group = www-data/g;" /etc/php5/fpm/pool.d/www.conf
sed -i "s/^;listen.mode = 0660/listen.mode = 0660/g;" /etc/php5/fpm/pool.d/www.conf

service php5-fpm restart
echo ""
echo -e "${CBLUE}Configuration PHP$CEND     ${CGREEN}Done !$CEND"
echo ""

mkdir -p /etc/nginx/passwd /etc/nginx/ssl
touch /etc/nginx/passwd/rutorrent_passwd
chmod 640 /etc/nginx/passwd/rutorrent_passwd

# configuration serveur web

# nginx.conf
cat <<'EOF' >  /etc/nginx/nginx.conf
user www-data;
worker_processes auto;

pid /var/run/nginx.pid;
events { worker_connections 1024; }

http {
	include /etc/nginx/mime.types;
	default_type  application/octet-stream;

	access_log /var/log/nginx/access.log combined;
	error_log /var/log/nginx/error.log error;

	sendfile on;
	keepalive_timeout 20;
	keepalive_disable msie6;
	keepalive_requests 100;
	tcp_nopush on;
	tcp_nodelay off;
	server_tokens off;

	gzip on;
	gzip_buffers 16 8k;
	gzip_comp_level 5;
	gzip_disable "msie6";
	gzip_min_length 20;
	gzip_proxied any;
	gzip_types text/plain text/css application/json  application/x-javascript text/xml application/xml application/xml+rss  text/javascript;
	gzip_vary on;

	include /etc/nginx/sites-enabled/*.conf;
}
EOF

# php
cat <<'EOF' >  /etc/nginx/conf.d/php
location ~ \.php$ {
	fastcgi_index index.php;
	fastcgi_pass unix:/var/run/php5-fpm.sock;
	fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
	include /etc/nginx/fastcgi_params;
}
EOF

# cache
cat <<'EOF' > /etc/nginx/conf.d/cache
location ~* \.(jpg|jpeg|gif|css|png|js|woff|ttf|svg|eot)$ {
	expires 30d;
	access_log off;
}

location ~* \.(eot|ttf|woff|svg)$ {
	add_header Acccess-Control-Allow-Origin *;
}
EOF

# configuration du vhost
mkdir /etc/nginx/sites-enabled
touch /etc/nginx/sites-enabled/rutorrent.conf

# rutorrent.conf
cat <<'EOF' >  /etc/nginx/sites-enabled/rutorrent.conf
server {
	listen 80 default_server;
	listen 443 default_server ssl;
	server_name _;

	index index.html index.php;
	charset utf-8;
	client_max_body_size 10M;

	ssl_certificate /etc/nginx/ssl/server.crt;
	ssl_certificate_key /etc/nginx/ssl/server.key;

	access_log /var/log/nginx/rutorrent-access.log combined;
	error_log /var/log/nginx/rutorrent-error.log error;

	error_page 500 502 503 504 /50x.html;
	location = /50x.html { root /usr/share/nginx/html; }

	auth_basic "seedbox";
	auth_basic_user_file "/etc/nginx/passwd/rutorrent_passwd";

	location = /favicon.ico {
		access_log off;
		log_not_found off;
	}

	## début config accueil serveur ##

	location ^~ / {
	    root /var/www/base;
	    include /etc/nginx/conf.d/php;
	    include /etc/nginx/conf.d/cache;
	    satisfy any;
	    allow all;
	}

	## fin config accueil serveur ##

	## début config proxy ##
#
#	#location ^~ /proxy {
#	  root /var/www;
#    include /etc/nginx/conf.d/php;
#	    include /etc/nginx/conf.d/cache;
#	}
#
	## fin config proxy ##

	## début config rutorrent ##

	location ^~ /rutorrent {
	    root /var/www;
	    include /etc/nginx/conf.d/php;
	    include /etc/nginx/conf.d/cache;

	    location ~ /\.svn {
		    deny all;
	    }

	    location ~ /\.ht {
		    deny all;
	    }
	}

	location ^~ /rutorrent/conf/ {
		deny all;
	}

	location ^~ /rutorrent/share/ {
		deny all;
	}

	## fin config rutorrent ##

	## début config munin ##

	location ^~ /graph {
	    root /var/www;
	    include /etc/nginx/conf.d/php;
	    include /etc/nginx/conf.d/cache;
	}

	location ^~ /graph/img {
	    root /var/www;
	    include /etc/nginx/conf.d/php;
	    include /etc/nginx/conf.d/cache;
	    error_log /dev/null crit;
	}

	location ^~ /monitoring {
	    root /var/www;
	    include /etc/nginx/conf.d/php;
	    include /etc/nginx/conf.d/cache;
	}

	## fin config munin ##

	## début config seedbox-manager ##

	location ^~ /seedbox-manager {
	alias /var/www/seedbox-manager/public;
	    include /etc/nginx/conf.d/php-manager;
	    include /etc/nginx/conf.d/cache;
	}

        ## fin config seedbox-manager ##

        ## config utilisateurs  ##
EOF
echo ""
echo -e "${CBLUE}Configuration Nginx$CEND     ${CGREEN}Done !$CEND"
echo ""

# installation munin
sed -i "s/#dbdir[[:blank:]]\/var\/lib\/munin/dbdir \/var\/lib\/munin/g;" /etc/munin/munin.conf
sed -i "s/#htmldir[[:blank:]]\/var\/cache\/munin\/www/htmldir \/var\/www\/monitoring/g;" /etc/munin/munin.conf
sed -i "s/#logdir[[:blank:]]\/var\/log\/munin/logdir \/var\/log\/munin/g;" /etc/munin/munin.conf
sed -i "s/#rundir[[:blank:]][[:blank:]]\/var\/run\/munin/rundir \/var\/run\/munin/g;" /etc/munin/munin.conf
sed -i "s/#max_size_x[[:blank:]]4000/max_size_x 5000/g;" /etc/munin/munin.conf
sed -i "s/#max_size_y[[:blank:]]4000/max_size_x 5000/g;" /etc/munin/munin.conf

mkdir /var/www/monitoring
chown munin:munin /var/www/monitoring

cd /usr/share/munin/plugins

wget https://raw.github.com/munin-monitoring/contrib/master/plugins/rtorrent/rtom_mem
wget https://raw.github.com/munin-monitoring/contrib/master/plugins/rtorrent/rtom_peers
wget https://raw.github.com/munin-monitoring/contrib/master/plugins/rtorrent/rtom_spdd
wget https://raw.github.com/munin-monitoring/contrib/master/plugins/rtorrent/rtom_vol

cp /usr/share/munin/plugins/rtom_mem /usr/share/munin/plugins/rtom_"$USER"_mem
cp /usr/share/munin/plugins/rtom_peers /usr/share/munin/plugins/rtom_"$USER"_peers
cp /usr/share/munin/plugins/rtom_spdd /usr/share/munin/plugins/rtom_"$USER"_spdd
cp /usr/share/munin/plugins/rtom_vol /usr/share/munin/plugins/rtom_"$USER"_vol

chmod 755 /usr/share/munin/plugins/rtom*

ln -s /usr/share/munin/plugins/rtom_"$USER"_mem /etc/munin/plugins/rtom_"$USER"_mem
ln -s /usr/share/munin/plugins/rtom_"$USER"_peers /etc/munin/plugins/rtom_"$USER"_peers
ln -s /usr/share/munin/plugins/rtom_"$USER"_spdd /etc/munin/plugins/rtom_"$USER"_spdd
ln -s /usr/share/munin/plugins/rtom_"$USER"_vol /etc/munin/plugins/rtom_"$USER"_vol

echo "
[rtom_@USER@_*]
user @USER@
env.ip 127.0.0.1
env.port @PORT@
env.diff yes
env.category @USER@">> /etc/munin/plugin-conf.d/munin-node

sed -i "s/@USER@/$USER/g;" /etc/munin/plugin-conf.d/munin-node
sed -i "s/@PORT@/$PORT/g;" /etc/munin/plugin-conf.d/munin-node

/etc/init.d/munin-node restart

echo "
rtom_@USER@_peers.graph_width 700
rtom_@USER@_peers.graph_height 500
rtom_@USER@_spdd.graph_width 700
rtom_@USER@_spdd.graph_height 500
rtom_@USER@_vol.graph_width 700
rtom_@USER@_vol.graph_height 500
rtom_@USER@_mem.graph_width 700
rtom_@USER@_mem.graph_height 500">> /etc/munin/munin.conf

sed -i "s/@USER@/$USER/g;" /etc/munin/munin.conf

cp -R /tmp/install-rutorrent/graph /var/www/graph

echo ""
echo -e "${CBLUE}Configuration Munin$CEND     ${CGREEN}Done !$CEND"
echo ""

# SSL configuration #

#!/bin/bash

openssl req -new -x509 -days 3658 -nodes -newkey rsa:2048 -out /etc/nginx/ssl/server.crt -keyout /etc/nginx/ssl/server.key<<EOF
RU
Russia
Moskva
wtf
wtf LTD
wtf.org
contact@wtf.org
EOF

service nginx restart

# installation Seedbox-Manager

## composer
cd /tmp
curl -s http://getcomposer.org/installer | php
mv /tmp/composer.phar /usr/bin/composer
chmod +x /usr/bin/composer
echo ""
echo -e "${CBLUE}Installation de Composer$CEND     ${CGREEN}Done !$CEND"
echo ""

## nodejs
wget -N http://nodejs.org/dist/node-latest.tar.gz
tar xzvf node-latest.tar.gz && cd node-v*
./configure
make && make install
echo ""
echo -e "${CBLUE}Installation de Nodejs$CEND     ${CGREEN}Done !$CEND"
echo ""

## bower
npm install -g bower
echo ""
echo -e "${CBLUE}Installation de bower$CEND     ${CGREEN}Done !$CEND"
echo ""

## app
cd /var/www
git clone https://github.com/Magicalex/seedbox-manager.git
cd ./seedbox-manager/
composer install
bower install --allow-root --config.interactive=false
chown -R www-data:www-data /var/www/seedbox-manager/
## conf app
cd ./source-reboot-rtorrent/
chmod +x install.sh
./install.sh

cp -R /tmp/install-rutorrent/theme/sm/SpiritOfBonobo /var/www/seedbox-manager/public/themes/SpiritOfBonobo
chown -R www-data:www-data /var/www/seedbox-manager/public/themes/SpiritOfBonobo

cat <<'EOF' >  /etc/nginx/conf.d/php-manager
location ~ \.php$ {
    root /var/www/seedbox-manager/public;
    include /etc/nginx/fastcgi_params;
    fastcgi_index index.php;
    fastcgi_pass unix:/var/run/php5-fpm.sock;
    fastcgi_param SCRIPT_FILENAME $document_root/index.php;
}

EOF

service nginx restart

## conf user
cd /var/www/seedbox-manager/conf/users/
mkdir $USER

cat <<'EOF' >  /var/www/seedbox-manager/conf/users/$USER/config.ini
; Manager de seedbox (adapté pour le tuto de lufki.org)
;
; Fichier de configuration :
; yes ou no pour activer les modules
; Si vous n'avez pas de nom de domaine, indiquez l'ip (ex: http://XX.XX.XX.XX/rutorrent)

[user]
active_bloc_info = yes
user_directory = "/home/mannix/"
scgi_folder = "/RPC1"
theme = "Oblivion"
owner = yes

[nav]
data_link = "url = https://lufki.org/rutorrent, name = rutorrent
url = https://proxy.lufki.org, name = proxy
url = https://graph.lufki.org, name = graph
url = https://log.lufki.org, name = log web
url = https://monitoring.lufki.org, name = munin"

[ftp]
active_ftp = yes
port_ftp = "21"
port_sftp = "22"

[rtorrent]
active_reboot = yes

[support]
active_support = yes
adresse_mail = "wtf@lufki.org"

[logout]
url_redirect = "http://cakebox.lufki.org"

EOF
sed -i "s/\"\/\"/\"\/home\/$USER\"/g;" /var/www/seedbox-manager/conf/users/$USER/config.ini
sed -i "s/rutorrent.lufki.org/$IP\/rutorrent\//g;" /var/www/seedbox-manager/conf/users/$USER/config.ini
sed -i "s/proxy.lufki.org/$IP\/proxy\//g;" /var/www/seedbox-manager/conf/users/$USER/config.ini
sed -i "s/graph.lufki.org/$IP\/graph\/$USER.php/g;" /var/www/seedbox-manager/conf/users/$USER/config.ini
sed -i "s/log.lufki.org/$IP\/rutorrent\/logserver\/access.html/g;" /var/www/seedbox-manager/conf/users/$USER/config.ini
sed -i "s/monitoring.lufki.org/$IP\/monitoring\//g;" /var/www/seedbox-manager/conf/users/$USER/config.ini
sed -i "s/RPC1/$USERMAJ/g;" /var/www/seedbox-manager/conf/users/$USER/config.ini
sed -i "s/wtf@lufki.org/$EMAIL/g;" /var/www/seedbox-manager/conf/users/$USER/config.ini

# verrouillage option parametre seedbox-manager
rm /var/www/seedbox-manager/public/themes/default/template/header.html
cat <<'EOF' >  /var/www/seedbox-manager/public/themes/default/template/header.html
<div class="container">
    <div class="navbar-header">
        <button type="button" class="navbar-toggle" data-toggle="collapse" data-target=".phone-menu">
            <span class="sr-only">Toggle navigation</span>
            <span class="icon-bar"></span>
            <span class="icon-bar"></span>
            <span class="icon-bar"></span>
        </button>
        <a class="navbar-brand" href="index.php">Seedbox Manager</a>
    </div>
    <nav class="collapse navbar-collapse phone-menu">
        <ul class="nav navbar-nav">
        {% for link in user.get_all_links %}
            <li class="nav-link"><a href="{{ link.url }}">{{ link.name }}</a></li>
        {% endfor %}
        </ul>
        <ul class="nav navbar-nav navbar-right">
            <li class="dropdown">
                <a href="#" class="dropdown-toggle user" data-toggle="dropdown"><i class="glyphicon glyphicon-user"></i> {{ userName }} <b class="caret"></b></a>
                <ul class="dropdown-menu">
                    {% if user.is_owner == true %}
                    <li><a href="?option"><i class="glyphicon glyphicon-wrench"></i> Paramètres</a></li>
                    <li><a href="?admin"><i class="glyphicon glyphicon-cog"></i> Administration</a></li>
                    {% endif %}
                    <li><a class="aboutlink" data-toggle="modal" href="#popupinfo"><i class="glyphicon glyphicon-info-sign"></i> A propos</a></li>
                    <li>
                        <a id="logout" href="#logout" title="Se déconnecter" data-host="{{ host }}" data-urlredirect="{{ serveur.logout_url_redirect }}">
                            <strong><i class="glyphicon glyphicon-log-out"></i> Déconnexion</strong>
                        </a>
                    </li>
                </ul>
            </li>
        </ul>
    </nav>
</div>

EOF

chown -R www-data:www-data /var/www/seedbox-manager/conf/users/
chown -R www-data:www-data /var/www/seedbox-manager/public/themes/default/template/header.html
echo ""
echo -e "${CBLUE}Installation de Seedbox-Manager$CEND     ${CGREEN}Done !$CEND"
echo ""

# logrotate
rm /etc/logrotate.d/nginx && touch /etc/logrotate.d/nginx
cat <<'EOF' >  /etc/logrotate.d/nginx
/var/log/nginx/*.log {
	daily
	missingok
	rotate 7
	compress
	delaycompress
	notifempty
	create 640 root
	sharedscripts
		postrotate
			[ -f /var/run/nginx.pid ] && kill -USR1 `cat /var/run/nginx.pid`
	endscript
}
EOF

# script logs html ccze
mkdir /var/www/rutorrent/logserver
cd /usr/share/scripts-perso

cat <<'EOF' >  /usr/share/scripts-perso/logserver.sh
#!/bin/bash
#
if [ -e /var/log/nginx/rutorrent-access.log.1 ]; then
	# Récupération des logs (J et J-1) et fusion
	cp /var/log/nginx/rutorrent-access.log /tmp/access.log.0
	cp /var/log/nginx/rutorrent-access.log.1 /tmp/access.log.1
	cd /tmp
	cat access.log.1 access.log.0 > access.log
else
	cd /tmp
	cp /var/log/nginx/rutorrent-access.log /tmp/access.log
fi

sed -i '/plugins/d' access.log
sed -i '/getsettings.php/d' access.log
sed -i '/setsettings.php/d' access.log
sed -i '/@USERMAJ@\ HTTP/d' access.log
ccze -h < /tmp/access.log > /var/www/rutorrent/logserver/access.html
EOF

sed -i "s/@USERMAJ@/$USERMAJ/g;" /usr/share/scripts-perso/logserver.sh
chmod +x logserver.sh

echo ""
echo -e "${CBLUE}Configuration Logs html et Logrotate$CEND     ${CGREEN}Done !$CEND"
echo ""

# SSH config
sed -i "s/Subsystem[[:blank:]]sftp[[:blank:]]\/usr\/lib\/openssh\/sftp-server/Subsystem sftp internal-sftp/g;" /etc/ssh/sshd_config
sed -i "s/UsePAM/#UsePAM/g;" /etc/ssh/sshd_config

# chroot user
echo "Match User $USER
ChrootDirectory /home/$USER">> /etc/ssh/sshd_config

service ssh restart
echo ""
echo -e "${CBLUE}Configuration SSH$CEND     ${CGREEN}Done !$CEND"
echo ""

# .rtorrent.rc conf
cat <<'EOF' >  /home/$USER/.rtorrent.rc
scgi_port = 127.0.0.1:5001
encoding_list = UTF-8
port_range = 49152-49163
port_random = yes
check_hash = no
directory = /home/@USER@/
session = /home/@USER@/.session
encryption = allow_incoming, try_outgoing, enable_retry
schedule = watch_directory,1,1,"load_start=/home/@USER@/watch/*.torrent"
schedule = untied_directory,5,5,"stop_untied=/home/@USER@/watch/*.torrent"
schedule = espace_disque_insuffisant,1,30,close_low_diskspace=500M
use_udp_trackers = yes
dht = off
peer_exchange = no
min_peers = 40
max_peers = 100
min_peers_seed = -1
max_peers_seed = -1
max_uploads = 15
execute = {sh,-c,/usr/bin/php /var/www/rutorrent/php/initplugins.php @USER@ &}
EOF
sed -i "s/@USER@/$USER/g;" /home/$USER/.rtorrent.rc

# permissions
chown -R $USER:$USER /home/$USER
chown root:$USER /home/$USER
chmod 755 /home/$USER

# user rtorrent.conf config
echo "
        location /$USERMAJ {
            include scgi_params;
            scgi_pass 127.0.0.1:5001; #ou socket : unix:/home/username/.session/username.socket
            auth_basic \"seedbox\";
            auth_basic_user_file \"/etc/nginx/passwd/rutorrent_passwd_$USER\";
        }
}">> /etc/nginx/sites-enabled/rutorrent.conf

mkdir /var/www/rutorrent/conf/users/$USER

# config.php
cat <<'EOF' >  /var/www/rutorrent/conf/users/$USER/config.php
<?php
$topDirectory = '/home/@USER@';
$scgi_port = 5001;
$scgi_host = '127.0.0.1';
$XMLRPCMountPoint = '/@USERMAJ@';
EOF
sed -i "s/@USER@/$USER/g;" /var/www/rutorrent/conf/users/$USER/config.php
sed -i "s/@USERMAJ@/$USERMAJ/g;" /var/www/rutorrent/conf/users/$USER/config.php

# plugin.ini
cat <<'EOF' >  /var/www/rutorrent/conf/users/$USER/plugins.ini
[default]
enabled = user-defined
canChangeToolbar = yes
canChangeMenu = yes
canChangeOptions = yes
canChangeTabs = yes
canChangeColumns = yes
canChangeStatusBar = yes
canChangeCategory = yes
canBeShutdowned = yes
[ipad]
enabled = yes
[httprpc]
enabled = no
[retrackers]
enabled = no
[rpc]
enabled = no
[rutracker_check]
enabled = no
[chat]
enabled = yes
EOF

# script rtorrent
cat <<'EOF' >  /etc/init.d/$USER-rtorrent
#!/bin/bash
 
### BEGIN INIT INFO
# Provides:                rtorrent
# Required-Start:       
# Required-Stop:       
# Default-Start:          2 3 4 5
# Default-Stop:          0 1 6
# Short-Description:  Start daemon at boot time
# Description:           Start-Stop rtorrent user session
### END INIT INFO
 
user="@USER@"
 
# the full path to the filename where you store your rtorrent configuration
config="/home/@USER@/.rtorrent.rc"
 
# set of options to run with
options=""
 
# default directory for screen, needs to be an absolute path
base="/home/@USER@"
 
# name of screen session
srnname="rtorrent"
 
# file to log to (makes for easier debugging if something goes wrong)
logfile="/var/log/rtorrentInit.log"
#######################
###END CONFIGURATION###
#######################
PATH=/usr/bin:/usr/local/bin:/usr/local/sbin:/sbin:/bin:/usr/sbin
DESC="rtorrent"
NAME=rtorrent
DAEMON=$NAME
SCRIPTNAME=/etc/init.d/$NAME
 
checkcnfg() {
    exists=0
    for i in `echo "$PATH" | tr ':' '\n'` ; do
        if [ -f $i/$NAME ] ; then
            exists=1
            break
        fi
    done
    if [ $exists -eq 0 ] ; then
        echo "cannot find rtorrent binary in PATH $PATH" | tee -a "$logfile" >&2
        exit 3
    fi
    if ! [ -r "${config}" ] ; then
        echo "cannot find readable config ${config}. check that it is there and permissions are appropriate" | tee -a "$logfile" >&2
        exit 3
    fi
    session=`getsession "$config"`
    if ! [ -d "${session}" ] ; then
        echo "cannot find readable session directory ${session} from config ${config}. check permissions" | tee -a "$logfile" >&2
        exit 3
 
        fi
 
}
 
d_start() {
 
  [ -d "${base}" ] && cd "${base}"
 
  stty stop undef && stty start undef
  su -c "screen -ls | grep -sq "\.${srnname}[[:space:]]" " ${user} || su -c "screen -dm -S ${srnname} 2>&1 1>/dev/null" ${user} | tee -a "$logfile" >&2
  su -c "screen -S "${srnname}" -X screen rtorrent ${options} 2>&1 1>/dev/null" ${user} | tee -a "$logfile" >&2
}
 
d_stop() {
    session=`getsession "$config"`
    if ! [ -s ${session}/rtorrent.lock ] ; then
        return
    fi
    pid=`cat ${session}/rtorrent.lock | awk -F: '{print($2)}' | sed "s/[^0-9]//g"`
    if ps -A | grep -sq ${pid}.*rtorrent ; then # make sure the pid doesn't belong to another process
        kill -s INT ${pid}
    fi
}
 
getsession() {
    session=`cat "$1" | grep "^[[:space:]]*session[[:space:]]*=" | sed "s/^[[:space:]]*session[[:space:]]*=[[:space:]]*//" `
    echo $session
}
 
checkcnfg
 
case "$1" in
  start)
    echo -n "Starting $DESC: $NAME"
    d_start
    echo "."
    ;;
  stop)
    echo -n "Stopping $DESC: $NAME"
    d_stop
    echo "."
    ;;
  restart|force-reload)
    echo -n "Restarting $DESC: $NAME"
    d_stop
    sleep 1
    d_start
    echo "."
    ;;
  *)
    echo "Usage: $SCRIPTNAME {start|stop|restart|force-reload}" >&2
    exit 1
    ;;
esac
 
exit 0
EOF

sed -i "s/@USER@/$USER/g;" /etc/init.d/$USER-rtorrent

# configuration script rtorrent
chmod +x /etc/init.d/$USER-rtorrent

# write out current crontab
crontab -l > rtorrentdem

# echo new cron into cron file
echo "$UPGEOIP 2 9 * * sh /usr/share/scripts-perso/updateGeoIP.sh > /dev/null 2>&1
0 */2 * * * sh /usr/share/scripts-perso/logserver.sh > /dev/null 2>&1
* * * * * if ! ( ps -U $USER | grep rtorrent > /dev/null ); then /etc/init.d/$USER-rtorrent start; fi > /dev/null 2>&1" >> rtorrentdem

# install new cron file
crontab rtorrentdem
rm rtorrentdem

#clear

# démarrage de rtorrent
/etc/init.d/$USER-rtorrent start

# htpasswd
htpasswd -cbs /etc/nginx/passwd/rutorrent_passwd $USER ${PASSNGINX}
htpasswd -cbs /etc/nginx/passwd/rutorrent_passwd_$USER $USER ${PASSNGINX}
chmod 640 /etc/nginx/passwd/*
chown -c www-data:www-data /etc/nginx/passwd/*
service nginx restart
echo ""
echo -e "${CBLUE}Configuration utilisateur ruTorrent$CEND     ${CGREEN}Done !$CEND"
echo ""

# conf fail2ban
cat <<'EOF' >  /etc/fail2ban/filter.d/nginx-auth.conf
## FICHIER /etc/fail2ban/filter.d/nginx-auth.conf ##
[Definition]

failregex = no user/password was provided for basic authentication.*client: <HOST>
            user .* was not found in.*client: <HOST>
            user .* password mismatch.*client: <HOST>

ignoreregex =
EOF

cat <<'EOF' >  /etc/fail2ban/filter.d/nginx-badbots.conf
# Fail2Ban configuration file nginx-badbots.conf
# Author: Patrik 'Sikevux' Greco <sikevux@sikevux.se>

[Definition]

# Option: failregex
# Notes.: regex to match access attempts to setup.php
# Values: TEXT

failregex = ^<HOST> .*?"GET.*?\/setup\.php.*?" .*?

# Anti w00tw00t
            ^<HOST> .*?"GET .*w00tw00t.* 404

# try to access to directory
            ^<HOST> .*?"GET .*admin.* 403
            ^<HOST> .*?"GET .*admin.* 404
            ^<HOST> .*?"GET .*install.* 404
            ^<HOST> .*?"GET .*dbadmin.* 404
            ^<HOST> .*?"GET .*myadmin.* 404
            ^<HOST> .*?"GET .*MyAdmin.* 404
            ^<HOST> .*?"GET .*mysql.* 404
            ^<HOST> .*?"GET .*websql.* 404
            ^<HOST> .*?"GET .*webdb.* 404
            ^<HOST> .*?"GET .*webadmin.* 404
            ^<HOST> .*?"GET \/pma\/.* 404
            ^<HOST> .*?"GET .*phppath.* 404
            ^<HOST> .*?"GET .*admm.* 404
            ^<HOST> .*?"GET .*databaseadmin.* 404
            ^<HOST> .*?"GET .*mysqlmanager.* 404
            ^<HOST> .*?"GET .*phpMyAdmin.* 404
            ^<HOST> .*?"GET .*xampp.* 404
            ^<HOST> .*?"GET .*sqlmanager.* 404
            ^<HOST> .*?"GET .*wp-content.* 404
            ^<HOST> .*?"GET .*wp-login.* 404
            ^<HOST> .*?"GET .*typo3.* 404
            ^<HOST> .*?"HEAD .*manager.* 404
            ^<HOST> .*?"GET .*manager.* 404
            ^<HOST> .*?"HEAD .*blackcat.* 404
            ^<HOST> .*?"HEAD .*sprawdza.php.* 404
            ^<HOST> .*?"GET .*HNAP1.* 404
            ^<HOST> .*?"GET .*vtigercrm.* 404
            ^<HOST> .*?"GET .*cgi-bin.* 404
            ^<HOST> .*?"GET .*webdav.* 404
            ^<HOST> .*?"GET .*web-console.* 404
            ^<HOST> .*?"GET .*manager.* 404
# Option: ignoreregex
# Notes.: regex to ignore. If this regex matches, the line is ignored.
# Values: TEXT
#
ignoreregex = true
EOF

cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
sed -i '93,$d' /etc/fail2ban/jail.local

echo "
[ssh]
enabled  = true
port     = ssh
filter   = sshd
logpath  = /var/log/auth.log
bantime = 600
banaction = iptables-multiport
maxretry = 5

[nginx-auth]
enabled  = true
port  = http,https
filter   = nginx-auth
logpath  = /var/log/nginx/*error.log
bantime = 600
banaction = iptables-multiport
maxretry = 10

[nginx-badbots]
enabled  = true
port  = http,https
filter = nginx-badbots
logpath = /var/log/nginx/*access.log
bantime = 600
banaction = iptables-multiport
maxretry = 5">> /etc/fail2ban/jail.local

/etc/init.d/fail2ban restart
echo ""
echo -e "${CBLUE}Configuration Fail2ban$CEND     ${CGREEN}Done !$CEND"
echo ""

# installation vsftpd
### echo -n -e "${CGREEN}Voulez vous installer un serveur FTP (y/n): $CEND"
###  read SERVFTP

### if [ "$SERVFTP" = "y" ]; then
$packetg install -y vsftpd

mv /etc/vsftpd.conf vsftpd.bak

echo "
# Configuration générale FTP/FTPS sur port 21 #
# Faite par Meister pour lufki.org
#
# Mode standalone
listen=YES
#
# Connexions anonymes 
anonymous_enable=NO
#
# Connexions des utilisateurs locaux 
local_enable=YES
#
# Ecriture des fichiers
write_enable=YES
#
# Masque local 022 (les fichiers ecrits auront les droits 755)
local_umask=022
#
# Ecriture de fichiers pour l'admin 
anon_upload_enable=YES
#
# Creation de repertoires
anon_mkdir_write_enable=YES
#
#message sur les répertoires
dirmessage_enable=YES
#
# Utilisation de l'heure locale
use_localtime=YES
#
# Activation des logs
xferlog_enable=YES
#
# Connexion sur le port 20 du serveur client  (ftp-data).
connect_from_port_20=YES
#
# Repertoire des logs.
xferlog_file=/var/log/vsftpd.log
xferlog_std_format=YES
#
# Timeout
idle_session_timeout=600
data_connection_timeout=120
#
# Bannière FTP
ftpd_banner=Bienvenue sur votre serveur FTP.
#
# Chroot des utilisateurs locaux 
chroot_local_user=YES
chroot_list_enable=YES
#
# Repertoire de chroot
chroot_list_file=/etc/vsftpd.chroot_list
secure_chroot_dir=/var/run/vsftpd/empty
#
# Fichier de config PAM
pam_service_name=vsftpd
#
#
# Configuration SSL 
#
#Chemin du certificat SSL
rsa_cert_file=/etc/ssl/private/vsftpd.cert.pem
rsa_private_key_file=/etc/ssl/private/vsftpd.key.pem
#
# Activation du SSL sur le serveur
ssl_enable=YES
allow_anon_ssl=NO
force_local_data_ssl=NO
force_local_logins_ssl=NO
#
# Acceptation des différentes versions du SLL
ssl_ciphers=HIGH
ssl_tlsv1=YES
ssl_sslv2=YES
ssl_sslv3=YES
#
max_per_ip=0
pasv_min_port=0
pasv_min_port=0
download_enable=YES
guest_enable=NO
pasv_enable=YES
port_enable=YES
pasv_promiscuous=NO
port_promiscuous=NO
#">> /etc/vsftpd.conf

# récupèration certificats nginx
cp -f /etc/nginx/ssl/server.crt  /etc/ssl/private/vsftpd.cert.pem
cp -f /etc/nginx/ssl/server.key  /etc/ssl/private/vsftpd.key.pem
			
touch /etc/vsftpd.chroot_list
/etc/init.d/vsftpd reload

echo "
[vsftpd]
enabled = true
port = ftp
filter = vsftpd
logpath = /var/log/vsftpd.log
bantime  = 600
banaction = iptables-multiport
maxretry = 5">> /etc/fail2ban/jail.local

/etc/init.d/fail2ban restart

echo ""
echo -e "${CBLUE}Installation VsFTPd$CEND     ${CGREEN}Done !$CEND"
echo ""
fi

# configuration page index munin
if [ ! -f /var/www/monitoring/localdomain/index.html ]; then
	MUNINROUTE=$"locahost/localhost"
else
	MUNINROUTE=$"localdomain/localhost.localdomain"
fi

ln -s /var/www/monitoring/"$MUNINROUTE"/rtom_"$USER"_mem-day.png /var/www/graph/img/rtom_"$USER"_mem-day.png
ln -s /var/www/monitoring/"$MUNINROUTE"/rtom_"$USER"_mem-week.png /var/www/graph/img/rtom_"$USER"_mem-week.png
ln -s /var/www/monitoring/"$MUNINROUTE"/rtom_"$USER"_mem-month.png /var/www/graph/img/rtom_"$USER"_mem-month.png

ln -s /var/www/monitoring/"$MUNINROUTE"/rtom_"$USER"_peers-day.png /var/www/graph/img/rtom_"$USER"_peers-day.png
ln -s /var/www/monitoring/"$MUNINROUTE"/rtom_"$USER"_peers-week.png /var/www/graph/img/rtom_"$USER"_peers-week.png
ln -s /var/www/monitoring/"$MUNINROUTE"/rtom_"$USER"_peers-month.png /var/www/graph/img/rtom_"$USER"_peers-month.png

ln -s /var/www/monitoring/"$MUNINROUTE"/rtom_"$USER"_spdd-day.png /var/www/graph/img/rtom_"$USER"_spdd-day.png
ln -s /var/www/monitoring/"$MUNINROUTE"/rtom_"$USER"_spdd-week.png /var/www/graph/img/rtom_"$USER"_spdd-week.png
ln -s /var/www/monitoring/"$MUNINROUTE"/rtom_"$USER"_spdd-month.png /var/www/graph/img/rtom_"$USER"_spdd-month.png

ln -s /var/www/monitoring/"$MUNINROUTE"/rtom_"$USER"_vol-day.png /var/www/graph/img/rtom_"$USER"_vol-day.png
ln -s /var/www/monitoring/"$MUNINROUTE"/rtom_"$USER"_vol-week.png /var/www/graph/img/rtom_"$USER"_vol-week.png
ln -s /var/www/monitoring/"$MUNINROUTE"/rtom_"$USER"_vol-month.png /var/www/graph/img/rtom_"$USER"_vol-month.png

cp /var/www/graph/user.php /var/www/graph/$USER.php

sed -i "s/@USER@/$USER/g;" /var/www/graph/$USER.php
sed -i "s/@USERROUTE@/$IP\/graph\/img/g;" /var/www/graph/$USER.php
sed -i "s/@RTOM@/rtom_$USER/g;" /var/www/graph/$USER.php
sed -i "s/@MANAGER@/$IP\/seedbox-manager\//g;" /var/www/graph/$USER.php
sed -i "s/@RUTORRENT@/$IP\/rutorrent\//g;" /var/www/graph/$USER.php

chown -R www-data:www-data /var/www/graph

# log users
echo "maillog">> /var/www/rutorrent/histo.log
echo "userlog">> /var/www/rutorrent/histo.log
sed -i "s/maillog/$EMAIL/g;" /var/www/rutorrent/histo.log
sed -i "s/userlog/$USER:5001/g;" /var/www/rutorrent/histo.log

echo -e "${CBLUE}Installation terminée !$CEND"

echo ""
echo -e "${CGREEN}Gardez bien ces informations:$CEND"
echo -e "${CBLUE}Username: $CEND${CYELLOW}$USER$CEND"
echo -e "${CBLUE}Password: $CEND${CYELLOW}${PASSNGINX}$CEND"
echo -e "${CGREEN}Elles vous permettront de vous connecter sur ruTorrent,\nSeedbox-Manager et en FTP si choisi à l'installation.$CEND"
echo ""

# ajout utilisateur supplémentaire

while :; do
echo -n -e "${CGREEN}Voulez vous ajouter un autre utilisateur (y/n): $CEND"
read REPONSE

if [ "$REPONSE" = "n" ]; then

	# fin d'installation
	# génération page log html
	sh /usr/share/scripts-perso/logserver.sh
	ccze -h < /tmp/install.log > /var/www/base/aide/install.html
	echo ""
	echo -n -e "${CGREEN}Voulez vous redémarrer pour finaliser votre installation (y/n): $CEND"
	read REBOOT
	
	if [ "$REBOOT" = "n" ]; then
		echo -e "${CBLUE}Le log de l'installation est visible à cette adresse:$CEND"
		echo -e "${CYELLOW}http://$IP/aide/install.html$CEND"
		echo ""
		echo -e "${CRED}Pensez à redémarrer manuellement votre serveur avant utilisation !$CEND"
		echo ""
		echo -e "${CBLUE}Vous pourrez ensuite vous connecter sur ruTorrent:$CEND"
		echo -e "${CYELLOW}https://$IP/rutorrent/$CEND"
		echo ""
		echo -e "${CBLUE}Et dans la partie \"Administration\" de Seedbox-Manager\npour ajuster certains réglages:$CEND"
		echo -e "${CYELLOW}https://$IP/seedbox-manager/$CEND"
		echo ""
		# en attente de tutos "ajout & création de torrent" propres ;-)
		#echo -e "${CBLUE}Vous trouverez aussi quelques informations pour faire\nvos premiers pas à cette adresse:$CEND"
		#echo -e "${CYELLOW}http://$IP/aide/$CEND"
		echo ""
		echo -e "${CBLUE}           Bon download, restez en seed et à bientôt sur lufki.org$CEND"
		echo -e "${CBLUE}                  Ex_Rat - http://lufki.org/$CEND"
		echo ""
		exit 1
	fi

	if [ "$REBOOT" = "y" ]; then
		echo -e "${CBLUE}Le log de l'installation est visible à cette adresse:$CEND"
		echo -e "${CYELLOW}http://$IP/aide/install.html$CEND"
		echo ""
		echo ""
		echo -e "${CBLUE}Vous pourrez ensuite vous connecter sur ruTorrent:$CEND"
		echo -e "${CYELLOW}https://$IP/rutorrent/$CEND"
		echo ""
		echo -e "${CBLUE}Et dans la partie \"Administration\" de Seedbox-Manager\npour ajuster certains réglages:$CEND"
		echo -e "${CYELLOW}https://$IP/seedbox-manager/$CEND"
		echo ""
		# en attente de tutos "ajout & création de torrent" propres ;-)
		#echo -e "${CBLUE}Vous trouverez aussi quelques informations pour faire\nvos premiers pas à cette adresse:$CEND"
		#echo -e "${CYELLOW}http://$IP/aide/$CEND"
		echo ""
		echo -e "${CBLUE}           That's it, mate! You're Ready To Go!!$CEND"
		echo -e "${CBLUE}                 Never forget:/$CEND"
		echo -e "${CBLUE}                 <h1>SHARING IS CARING!!!</h1>/$CEND"
		echo ""
		reboot
		break
	fi
fi

if [ "$REPONSE" = "y" ]; then

# demande nom et mot de passe
echo ""
echo -n -e "${CGREEN}Entrez le nom de l'utilisateur (en minuscule): $CEND"
read USERSUP
echo ""
echo -e "${CGREEN}Entrez le mot de passe pour cet utilisateur,\nou appuyez sur \"$CEND${CYELLOW}Entrée$CEND${CGREEN}\" pour en générer un automatiquement: $CEND"
read REPPWDSUP
if [ "$REPPWDSUP" = "" ]; then
    while :; do
    AUTOPWDSUP=$(strings /dev/urandom | grep -o '[1-9A-NP-Za-np-z]' | head -n 8 | tr -d '\n')
    echo -e -n "${CGREEN}Voulez vous utiliser$CEND ${CYELLOW}$AUTOPWDSUP$CEND${CGREEN} comme mot de passe ? (y/n] : $CEND"
        read REPONSEPWDSUP
        if [ "$REPONSEPWDSUP" = "n" ]; then
            echo
        else
           PWDSUP=$AUTOPWDSUP
           break

       fi
    done
else
    PWDSUP=$REPPWDSUP
fi

# récupération 5% root sur /home/user si présent
FS=$(grep /home/$USERSUP /etc/fstab | cut -c 6-9)

if [ "$FS" = "" ]; then
	echo
else
    tune2fs -m 0 /dev/$FS
    mount -o remount /home/$USERSUP
fi

# variable passe nginx
PASSNGINXSUP=${PWDSUP}
echo ""

# ajout utilisateur
useradd -M -s /bin/bash "$USERSUP"

# création du mot de passe pour cet utilisateur
echo "${USERSUP}:${PWDSUP}" | chpasswd

# anti-bug /home/user déjà existant
mkdir -p /home/$USERSUP
chown -R $USERSUP:$USERSUP /home/$USERSUP

# variable utilisateur majuscule
USERMAJSUP=`echo $USERSUP | tr "[:lower:]" "[:upper:]"`

# variable mail
EMAIL=$(sed -n "1 p" /var/www/rutorrent/histo.log)

# création de dossier
su $USERSUP -c 'mkdir -p ~/watch ~/torrents ~/.session '

# calcul port
HISTO=$(cat /var/www/rutorrent/histo.log | wc -l)
PORTSUP=$(( 5001+$HISTO ))

# configuration munin
cp /usr/share/munin/plugins/rtom_mem /usr/share/munin/plugins/rtom_"$USERSUP"_mem
cp /usr/share/munin/plugins/rtom_peers /usr/share/munin/plugins/rtom_"$USERSUP"_peers
cp /usr/share/munin/plugins/rtom_spdd /usr/share/munin/plugins/rtom_"$USERSUP"_spdd
cp /usr/share/munin/plugins/rtom_vol /usr/share/munin/plugins/rtom_"$USERSUP"_vol

chmod 755 /usr/share/munin/plugins/rtom*

ln -s /usr/share/munin/plugins/rtom_"$USERSUP"_mem /etc/munin/plugins/rtom_"$USERSUP"_mem
ln -s /usr/share/munin/plugins/rtom_"$USERSUP"_peers /etc/munin/plugins/rtom_"$USERSUP"_peers
ln -s /usr/share/munin/plugins/rtom_"$USERSUP"_spdd /etc/munin/plugins/rtom_"$USERSUP"_spdd
ln -s /usr/share/munin/plugins/rtom_"$USERSUP"_vol /etc/munin/plugins/rtom_"$USERSUP"_vol

echo "
[rtom_@USERSUP@_*]
user @USERSUP@
env.ip 127.0.0.1
env.port @PORTSUP@
env.diff yes
env.category @USERSUP@">> /etc/munin/plugin-conf.d/munin-node

sed -i "s/@USERSUP@/$USERSUP/g;" /etc/munin/plugin-conf.d/munin-node
sed -i "s/@PORTSUP@/$PORTSUP/g;" /etc/munin/plugin-conf.d/munin-node

/etc/init.d/munin-node restart

echo "
rtom_@USERSUP@_peers.graph_width 700
rtom_@USERSUP@_peers.graph_height 500
rtom_@USERSUP@_spdd.graph_width 700
rtom_@USERSUP@_spdd.graph_height 500
rtom_@USERSUP@_vol.graph_width 700
rtom_@USERSUP@_vol.graph_height 500
rtom_@USERSUP@_mem.graph_width 700
rtom_@USERSUP@_mem.graph_height 500">> /etc/munin/munin.conf

sed -i "s/@USERSUP@/$USERSUP/g;" /etc/munin/munin.conf

# config .rtorrent.rc
cat <<'EOF' > /home/$USERSUP/.rtorrent.rc
scgi_port = 127.0.0.1:@PORTSUP@
encoding_list = UTF-8
port_range = 49152-49163
port_random = yes
check_hash = no
directory = /home/@USERSUP@/
session = /home/@USERSUP@/.session
encryption = allow_incoming, try_outgoing, enable_retry
schedule = watch_directory,1,1,"load_start=/home/@USERSUP@/watch/*.torrent"
schedule = untied_directory,5,5,"stop_untied=/home/@USERSUP@/watch/*.torrent"
schedule = espace_disque_insuffisant,1,30,close_low_diskspace=500M
use_udp_trackers = yes
dht = off
peer_exchange = no
min_peers = 40
max_peers = 100
min_peers_seed = 10
max_peers_seed = 50
max_uploads = 15
execute = {sh,-c,/usr/bin/php /var/www/rutorrent/php/initplugins.php @USERSUP@ &}
EOF
sed -i "s/@USERSUP@/$USERSUP/g;" /home/$USERSUP/.rtorrent.rc
sed -i "s/@PORTSUP@/$PORTSUP/g;" /home/$USERSUP/.rtorrent.rc

# user rtorrent.conf config
sed -i '$d' /etc/nginx/sites-enabled/rutorrent.conf
echo "
        location /$USERMAJSUP {
            include scgi_params;
            scgi_pass 127.0.0.1:$PORTSUP; #ou socket : unix:/home/username/.session/username.socket
            auth_basic \"seedbox\";
            auth_basic_user_file \"/etc/nginx/passwd/rutorrent_passwd_$USERSUP\";
        }">> /etc/nginx/sites-enabled/rutorrent.conf
echo "}" >> /etc/nginx/sites-enabled/rutorrent.conf

# logserver user config
sed -i '$d' /usr/share/scripts-perso/logserver.sh
echo "sed -i '/@USERMAJSUP@\ HTTP/d' access.log" >> /usr/share/scripts-perso/logserver.sh
sed -i "s/@USERMAJSUP@/$USERMAJSUP/g;" /usr/share/scripts-perso/logserver.sh
echo "ccze -h < /tmp/access.log > /var/www/rutorrent/logserver/access.html" >> /usr/share/scripts-perso/logserver.sh

mkdir /var/www/rutorrent/conf/users/$USERSUP

# config.php
cat <<'EOF' > /var/www/rutorrent/conf/users/$USERSUP/config.php
<?php
$topDirectory = '/home/@USERSUP@';
$scgi_port = @PORTSUP@;
$scgi_host = '127.0.0.1';
$XMLRPCMountPoint = '/@USERMAJSUP@';
EOF
sed -i "s/@USERSUP@/$USERSUP/g;" /var/www/rutorrent/conf/users/$USERSUP/config.php
sed -i "s/@USERMAJSUP@/$USERMAJSUP/g;" /var/www/rutorrent/conf/users/$USERSUP/config.php
sed -i "s/@PORTSUP@/$PORTSUP/g;" /var/www/rutorrent/conf/users/$USERSUP/config.php

# chroot user supplèmentaire
echo "Match User $USERSUP
ChrootDirectory /home/$USERSUP">> /etc/ssh/sshd_config

service ssh restart

## conf user seedbox-manager
cd /var/www/seedbox-manager/conf/users/
mkdir $USERSUP

cat <<'EOF' >  /var/www/seedbox-manager/conf/users/$USERSUP/config.ini
; Manager de seedbox (adapté pour le tuto de lufki.org)
;
; Fichier de configuration :
; yes ou no pour activer les modules
; Si vous n'avez pas de nom de domaine, indiquez l'ip (ex: http://XX.XX.XX.XX/rutorrent)

[user]
active_bloc_info = yes
user_directory = "/home/mannix/"
scgi_folder = "/RPC1"
theme = "Default"
owner = no

[nav]
data_link = "url = https://lufki.org/rutorrent, name = rutorrent
url = https://proxy.lufki.org, name = proxy
url = https://graph.lufki.org, name = graph"

[ftp]
active_ftp = yes
port_ftp = "21"
port_sftp = "22"

[rtorrent]
active_reboot = yes

[support]
active_support = yes
adresse_mail = "wtf@lufki.org"

[logout]
url_redirect = "http://cakebox.lufki.org"

EOF
sed -i "s/\"\/\"/\"\/home\/$USERSUP\"/g;" /var/www/seedbox-manager/conf/users/$USERSUP/config.ini
sed -i "s/rutorrent.lufki.org/$IP\/rutorrent\//g;" /var/www/seedbox-manager/conf/users/$USERSUP/config.ini
sed -i "s/proxy.lufki.org/$IP\/proxy\//g;" /var/www/seedbox-manager/conf/users/$USERSUP/config.ini
sed -i "s/graph.lufki.org/$IP\/graph\/$USERSUP.php/g;" /var/www/seedbox-manager/conf/users/$USERSUP/config.ini
sed -i "s/RPC1/$USERMAJSUP/g;" /var/www/seedbox-manager/conf/users/$USERSUP/config.ini
sed -i "s/darwinsblade@gmail.com/$EMAIL/g;" /var/www/seedbox-manager/conf/users/$USERSUP/config.ini

# plugin.ini
cat <<'EOF' >  /var/www/rutorrent/conf/users/$USERSUP/plugins.ini
[default]
enabled = user-defined
canChangeToolbar = yes
canChangeMenu = yes
canChangeOptions = yes
canChangeTabs = yes
canChangeColumns = yes
canChangeStatusBar = yes
canChangeCategory = yes
canBeShutdowned = yes
[ipad]
enabled = yes
[httprpc]
enabled = no
[retrackers]
enabled = no
[rpc]
enabled = no
[rutracker_check]
enabled = no
[chat]
enabled = yes
EOF

# permission
chown -R www-data:www-data /var/www/seedbox-manager/conf/users/
chown -R www-data:www-data /var/www/rutorrent
chown -R $USERSUP:$USERSUP /home/$USERSUP
chown root:$USERSUP /home/$USERSUP
chmod 755 /home/$USERSUP

# script rtorrent
cat <<'EOF' > /etc/init.d/$USERSUP-rtorrent
#!/bin/bash
 
### BEGIN INIT INFO
# Provides: rtorrent
# Required-Start:
# Required-Stop:
# Default-Start: 2 3 4 5
# Default-Stop: 0 1 6
# Short-Description: Start daemon at boot time
# Description: Start-Stop rtorrent user session
### END INIT INFO
 
user="@USERSUP@"
 
# the full path to the filename where you store your rtorrent configuration
config="/home/@USERSUP@/.rtorrent.rc"
 
# set of options to run with
options=""
 
# default directory for screen, needs to be an absolute path
base="/home/@USERSUP@"
 
# name of screen session
srnname="rtorrent"
 
# file to log to (makes for easier debugging if something goes wrong)
logfile="/var/log/rtorrentInit.log"
#######################
###END CONFIGURATION###
#######################
PATH=/usr/bin:/usr/local/bin:/usr/local/sbin:/sbin:/bin:/usr/sbin
DESC="rtorrent"
NAME=rtorrent
DAEMON=$NAME
SCRIPTNAME=/etc/init.d/$NAME
 
checkcnfg() {
    exists=0
    for i in `echo "$PATH" | tr ':' '\n'` ; do
        if [ -f $i/$NAME ] ; then
            exists=1
            break
        fi
    done
    if [ $exists -eq 0 ] ; then
        echo "cannot find rtorrent binary in PATH $PATH" | tee -a "$logfile" >&2
        exit 3
    fi
    if ! [ -r "${config}" ] ; then
        echo "cannot find readable config ${config}. check that it is there and permissions are appropriate" | tee -a "$logfile" >&2
        exit 3
    fi
    session=`getsession "$config"`
    if ! [ -d "${session}" ] ; then
        echo "cannot find readable session directory ${session} from config ${config}. check permissions" | tee -a "$logfile" >&2
        exit 3
 
        fi
 
}
 
d_start() {
 
  [ -d "${base}" ] && cd "${base}"
 
  stty stop undef && stty start undef
  su -c "screen -ls | grep -sq "\.${srnname}[[:space:]]" " ${user} || su -c "screen -dm -S ${srnname} 2>&1 1>/dev/null" ${user} | tee -a "$logfile" >&2
  su -c "screen -S "${srnname}" -X screen rtorrent ${options} 2>&1 1>/dev/null" ${user} | tee -a "$logfile" >&2
}
 
d_stop() {
    session=`getsession "$config"`
    if ! [ -s ${session}/rtorrent.lock ] ; then
        return
    fi
    pid=`cat ${session}/rtorrent.lock | awk -F: '{print($2)}' | sed "s/[^0-9]//g"`
    if ps -A | grep -sq ${pid}.*rtorrent ; then # make sure the pid doesn't belong to another process
        kill -s INT ${pid}
    fi
}
 
getsession() {
    session=`cat "$1" | grep "^[[:space:]]*session[[:space:]]*=" | sed "s/^[[:space:]]*session[[:space:]]*=[[:space:]]*//" `
    echo $session
}
 
checkcnfg
 
case "$1" in
  start)
    echo -n "Starting $DESC: $NAME"
    d_start
    echo "."
    ;;
  stop)
    echo -n "Stopping $DESC: $NAME"
    d_stop
    echo "."
    ;;
  restart|force-reload)
    echo -n "Restarting $DESC: $NAME"
    d_stop
    sleep 1
    d_start
    echo "."
    ;;
  *)
    echo "Usage: $SCRIPTNAME {start|stop|restart|force-reload}" >&2
    exit 1
    ;;
esac
 
exit 0
EOF

sed -i "s/@USERSUP@/$USERSUP/g;" /etc/init.d/$USERSUP-rtorrent
chmod +x /etc/init.d/$USERSUP-rtorrent

# crontab
crontab -l > rtorrentdem
echo "* * * * * if ! ( ps -U $USERSUP | grep rtorrent > /dev/null ); then /etc/init.d/$USERSUP-rtorrent start; fi > /dev/null 2>&1" >> rtorrentdem
crontab rtorrentdem
rm rtorrentdem

service $USERSUP-rtorrent restart

# htpasswd
htpasswd -bs /etc/nginx/passwd/rutorrent_passwd $USERSUP ${PASSNGINXSUP}
htpasswd -cbs /etc/nginx/passwd/rutorrent_passwd_$USERSUP $USERSUP ${PASSNGINXSUP}
chmod 640 /etc/nginx/passwd/*
chown -c www-data:www-data /etc/nginx/passwd/*
service nginx restart

# configuration page index munin
if [ ! -f /var/www/monitoring/localdomain/index.html ]; then
	MUNINROUTE=$"locahost/localhost"
else
	MUNINROUTE=$"localdomain/localhost.localdomain"
fi

ln -s /var/www/monitoring/"$MUNINROUTE"/rtom_"$USERSUP"_mem-day.png /var/www/graph/img/rtom_"$USERSUP"_mem-day.png
ln -s /var/www/monitoring/"$MUNINROUTE"/rtom_"$USERSUP"_mem-week.png /var/www/graph/img/rtom_"$USERSUP"_mem-week.png
ln -s /var/www/monitoring/"$MUNINROUTE"/rtom_"$USERSUP"_mem-month.png /var/www/graph/img/rtom_"$USERSUP"_mem-month.png

ln -s /var/www/monitoring/"$MUNINROUTE"/rtom_"$USERSUP"_peers-day.png /var/www/graph/img/rtom_"$USERSUP"_peers-day.png
ln -s /var/www/monitoring/"$MUNINROUTE"/rtom_"$USERSUP"_peers-week.png /var/www/graph/img/rtom_"$USERSUP"_peers-week.png
ln -s /var/www/monitoring/"$MUNINROUTE"/rtom_"$USERSUP"_peers-month.png /var/www/graph/img/rtom_"$USERSUP"_peers-month.png

ln -s /var/www/monitoring/"$MUNINROUTE"/rtom_"$USERSUP"_spdd-day.png /var/www/graph/img/rtom_"$USERSUP"_spdd-day.png
ln -s /var/www/monitoring/"$MUNINROUTE"/rtom_"$USERSUP"_spdd-week.png /var/www/graph/img/rtom_"$USERSUP"_spdd-week.png
ln -s /var/www/monitoring/"$MUNINROUTE"/rtom_"$USERSUP"_spdd-month.png /var/www/graph/img/rtom_"$USERSUP"_spdd-month.png

ln -s /var/www/monitoring/"$MUNINROUTE"/rtom_"$USERSUP"_vol-day.png /var/www/graph/img/rtom_"$USERSUP"_vol-day.png
ln -s /var/www/monitoring/"$MUNINROUTE"/rtom_"$USERSUP"_vol-week.png /var/www/graph/img/rtom_"$USERSUP"_vol-week.png
ln -s /var/www/monitoring/"$MUNINROUTE"/rtom_"$USERSUP"_vol-month.png /var/www/graph/img/rtom_"$USERSUP"_vol-month.png

cp /var/www/graph/user.php /var/www/graph/$USERSUP.php

sed -i "s/@USER@/$USERSUP/g;" /var/www/graph/$USERSUP.php
sed -i "s/@USERROUTE@/$IP\/graph\/img/g;" /var/www/graph/$USERSUP.php
sed -i "s/@RTOM@/rtom_$USERSUP/g;" /var/www/graph/$USERSUP.php
sed -i "s/@MANAGER@/$IP\/seedbox-manager\//g;" /var/www/graph/$USERSUP.php
sed -i "s/@RUTORRENT@/$IP\/rutorrent\//g;" /var/www/graph/$USERSUP.php

chown -R www-data:www-data /var/www/graph

# log users
echo "userlog">> /var/www/rutorrent/histo.log
sed -i "s/userlog/$USERSUP:$PORTSUP/g;" /var/www/rutorrent/histo.log

echo ""
echo -e "${CBLUE}Ajout de l'utilisateur terminé !$CEND"

echo ""
echo -e "${CGREEN}Gardez bien ces informations:$CEND"
echo -e "${CBLUE}Username: $CEND${CYELLOW}$USERSUP$CEND"
echo -e "${CBLUE}Password: $CEND${CYELLOW}${PASSNGINXSUP}$CEND"
echo -e "${CGREEN}Elles vous permettront de vous connecter sur ruTorrent,\nSeedbox-Manager et en FTP si choisi à l'installation.$CEND"
echo ""
fi
done

else

################################################
# lancement gestion des utilisateurs ruTorrent #
################################################

clear

# Contrôle installation
if [ ! -f /var/www/rutorrent/histo.log ]; then
	echo ""				
	echo -e "${CRED}     Votre installation n'est pas compatible avec cette version du script.$CEND"
	echo -e "${CRED}          Vous trouverez un utilitaire adapté sur http://lufki.org !$CEND"
	echo ""				
	exit 1
fi

# message d'accueil
echo ""
echo -e "${CBLUE}                  Utilitaire de gestion utilisateur ruTorrent$CEND"
echo ""

# logo
echo -e "${CBLUE}
                                      |          |_)         _|     
            __ \`__ \   _ \  __ \   _\` |  _ \  _\` | |  _ \   |    __|
            |   |   | (   | |   | (   |  __/ (   | |  __/   __| |   
           _|  _|  _|\___/ _|  _|\__,_|\___|\__,_|_|\___|_)_|  _|   

$CEND"
echo ""

# mise en garde
echo -e "${CRED}         Attention, si vous avez modifié votre fichier rutorrent.conf$CENS"
echo -e "${CRED}         depuis la fin de l'installation automatique, le script peut$CEND"
echo -e "${CRED}         ne pas fonctionner normalement. Faites le manuellement !$CEND"
echo ""
echo -n -e "${CGREEN}Voulez vous continuer? (y/n): $CEND"
read VALIDE
if [ "$VALIDE" = "n" ]; then
	echo ""
	echo -e "${CBLUE}           That's it, mate!$CEND"
	echo -e "${CBLUE}                Ready To Go./$CEND"
	echo ""
	exit 1
fi

if [ "$VALIDE" = "y" ]; then

# Boucle ajout/suppression utilisateur
while :; do

# menu gestion multi-utilisateurs
echo ""
echo -e $CBLUE"Choisissez une option.$CEND"
echo -e "$CYELLOW 1$CEND $CGREEN: Ajouter un utilisateur$CEND"
echo -e "$CYELLOW 2$CEND $CGREEN: Suspendre un utilisateur$CEND"
echo -e "$CYELLOW 3$CEND $CGREEN: Rétablir un utilisateur$CEND"
echo -e "$CYELLOW 4$CEND $CGREEN: Modifier un mot de passe$CEND"
echo -e "$CYELLOW 5$CEND $CGREEN: Supprimer un utilisateur$CEND"
echo -e "$CYELLOW 6$CEND $CGREEN: Sortir$CEND"
echo -n -e "${CBLUE}Numéro: $CEND"
read OPTION

case $OPTION in
1)

# demande nom et mot de passe
echo -n -e "${CGREEN}Entrez le nom de l'utilisateur (en minuscule): $CEND"
read USER
echo ""
echo -e "${CGREEN}Entrez le mot de passe pour cet utilisateur,\nou appuyez sur \"$CEND${CYELLOW}Entrée$CEND${CGREEN}\" pour en générer un automatiquement: $CEND"
read REPPWD
if [ "$REPPWD" = "" ]; then
    while :; do
    AUTOPWD=$(strings /dev/urandom | grep -o '[1-9A-NP-Za-np-z]' | head -n 8 | tr -d '\n')
    echo -e -n "${CGREEN}Voulez vous utiliser$CEND ${CYELLOW}$AUTOPWD$CEND${CGREEN} comme mot de passe ? (y/n] : $CEND"
        read REPONSEPWD
        if [ "$REPONSEPWD" = "n" ]; then
            echo
        else
           PWD=$AUTOPWD
           break

       fi
    done
else
    PWD=$REPPWD
fi
echo ""

# récupération 5% root sur /home/user si présent
FS=$(grep /home/$USER /etc/fstab | cut -c 6-9)

if [ "$FS" = "" ]; then
	echo
else
    tune2fs -m 0 /dev/$FS
    mount -o remount /home/$USER
	echo ""
fi

# variable email (rétro compatible)
TESTMAIL=$(sed -n "1 p" /var/www/rutorrent/histo.log)
IFS="@"
set -- $TESTMAIL
if [ "${#@}" -ne 2 ];then
    EMAIL=contact@exemple.com
else
    EMAIL=$TESTMAIL
fi

# variable passe nginx
PASSNGINX=${PWD}
echo ""

# ajout utilisateur
useradd -M -s /bin/bash "$USER"

# création du mot de passe pour cet utilisateur
echo "${USER}:${PWD}" | chpasswd

# anti-bug /home/user déjà existant
mkdir -p /home/$USER
chown -R $USER:$USER /home/$USER

# variable utilisateur majuscule
USERMAJ=`echo $USER | tr "[:lower:]" "[:upper:]"`

# récupération IP serveur
IP=$(ifconfig | grep 'inet addr:' | grep -v inet6 | grep -vE '127\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | cut -d: -f2 | awk '{ print $1}' | head -1)
if [ "$IP" = "" ]; then
	IP=$(wget -qO- ipv4.icanhazip.com)
fi

su $USER -c 'mkdir -p ~/watch ~/torrents ~/.session '

# calcul port
HISTO=$(cat /var/www/rutorrent/histo.log | wc -l)
PORT=$(( 5001+$HISTO ))

# configuration munin
cp /usr/share/munin/plugins/rtom_mem /usr/share/munin/plugins/rtom_"$USER"_mem
cp /usr/share/munin/plugins/rtom_peers /usr/share/munin/plugins/rtom_"$USER"_peers
cp /usr/share/munin/plugins/rtom_spdd /usr/share/munin/plugins/rtom_"$USER"_spdd
cp /usr/share/munin/plugins/rtom_vol /usr/share/munin/plugins/rtom_"$USER"_vol

chmod 755 /usr/share/munin/plugins/rtom*

ln -s /usr/share/munin/plugins/rtom_"$USER"_mem /etc/munin/plugins/rtom_"$USER"_mem
ln -s /usr/share/munin/plugins/rtom_"$USER"_peers /etc/munin/plugins/rtom_"$USER"_peers
ln -s /usr/share/munin/plugins/rtom_"$USER"_spdd /etc/munin/plugins/rtom_"$USER"_spdd
ln -s /usr/share/munin/plugins/rtom_"$USER"_vol /etc/munin/plugins/rtom_"$USER"_vol

echo "
[rtom_@USER@_*]
user @USER@
env.ip 127.0.0.1
env.port @PORT@
env.diff yes
env.category @USER@">> /etc/munin/plugin-conf.d/munin-node

sed -i "s/@USER@/$USER/g;" /etc/munin/plugin-conf.d/munin-node
sed -i "s/@PORT@/$PORT/g;" /etc/munin/plugin-conf.d/munin-node

/etc/init.d/munin-node restart

echo "
rtom_@USER@_peers.graph_width 700
rtom_@USER@_peers.graph_height 500
rtom_@USER@_spdd.graph_width 700
rtom_@USER@_spdd.graph_height 500
rtom_@USER@_vol.graph_width 700
rtom_@USER@_vol.graph_height 500
rtom_@USER@_mem.graph_width 700
rtom_@USER@_mem.graph_height 500">> /etc/munin/munin.conf

sed -i "s/@USER@/$USER/g;" /etc/munin/munin.conf

# config .rtorrent.rc
cat <<'EOF' > /home/$USER/.rtorrent.rc
scgi_port = 127.0.0.1:@PORT@
encoding_list = UTF-8
port_range = 49152-49163
port_random = yes
check_hash = no
directory = /home/@USER@/
session = /home/@USER@/.session
encryption = allow_incoming, try_outgoing, enable_retry
schedule = watch_directory,1,1,"load_start=/home/@USER@/watch/*.torrent"
schedule = untied_directory,5,5,"stop_untied=/home/@USER@/watch/*.torrent"
schedule = espace_disque_insuffisant,1,30,close_low_diskspace=500M
use_udp_trackers = yes
dht = off
peer_exchange = no
min_peers = 40
max_peers = 200
min_peers_seed = -1
max_peers_seed = -1
max_uploads = 15
execute = {sh,-c,/usr/bin/php /var/www/rutorrent/php/initplugins.php @USER@ &}
EOF
sed -i "s/@USER@/$USER/g;" /home/$USER/.rtorrent.rc
sed -i "s/@PORT@/$PORT/g;" /home/$USER/.rtorrent.rc

# user rtorrent.conf config
sed -i '$d' /etc/nginx/sites-enabled/rutorrent.conf
echo "
        location /$USERMAJ {
            include scgi_params;
            scgi_pass 127.0.0.1:$PORT; #ou socket : unix:/home/username/.session/username.socket
            auth_basic \"seedbox\";
            auth_basic_user_file \"/etc/nginx/passwd/rutorrent_passwd_$USER\";
        }">> /etc/nginx/sites-enabled/rutorrent.conf
echo "}" >> /etc/nginx/sites-enabled/rutorrent.conf

# logserver user config
sed -i '$d' /usr/share/scripts-perso/logserver.sh
echo "sed -i '/@USERMAJ@\ HTTP/d' access.log" >> /usr/share/scripts-perso/logserver.sh
sed -i "s/@USERMAJ@/$USERMAJ/g;" /usr/share/scripts-perso/logserver.sh
echo "ccze -h < /tmp/access.log > /var/www/rutorrent/logserver/access.html" >> /usr/share/scripts-perso/logserver.sh

mkdir /var/www/rutorrent/conf/users/$USER

# config.php
cat <<'EOF' > /var/www/rutorrent/conf/users/$USER/config.php
<?php
$topDirectory = '/home/@USER@';
$scgi_port = @PORT@;
$scgi_host = '127.0.0.1';
$XMLRPCMountPoint = '/@USERMAJ@';
EOF
sed -i "s/@USER@/$USER/g;" /var/www/rutorrent/conf/users/$USER/config.php
sed -i "s/@USERMAJ@/$USERMAJ/g;" /var/www/rutorrent/conf/users/$USER/config.php
sed -i "s/@PORT@/$PORT/g;" /var/www/rutorrent/conf/users/$USER/config.php

# plugin.ini
cat <<'EOF' >  /var/www/rutorrent/conf/users/$USER/plugins.ini
[default]
enabled = user-defined
canChangeToolbar = yes
canChangeMenu = yes
canChangeOptions = yes
canChangeTabs = yes
canChangeColumns = yes
canChangeStatusBar = yes
canChangeCategory = yes
canBeShutdowned = yes
[ipad]
enabled = yes
[httprpc]
enabled = no
[retrackers]
enabled = no
[rpc]
enabled = no
[rutracker_check]
enabled = no
[chat]
enabled = yes
EOF

# chroot user supplémentaire
echo "Match User $USER
ChrootDirectory /home/$USER">> /etc/ssh/sshd_config

service ssh restart

# permission
chown -R www-data:www-data /var/www/rutorrent
chown -R $USER:$USER /home/$USER
chown root:$USER /home/$USER
chmod 755 /home/$USER

# script rtorrent
cat <<'EOF' > /etc/init.d/$USER-rtorrent
#!/bin/bash
 
### BEGIN INIT INFO
# Provides: rtorrent
# Required-Start:
# Required-Stop:
# Default-Start: 2 3 4 5
# Default-Stop: 0 1 6
# Short-Description: Start daemon at boot time
# Description: Start-Stop rtorrent user session
### END INIT INFO
 
user="@USER@"
 
# the full path to the filename where you store your rtorrent configuration
config="/home/@USER@/.rtorrent.rc"
 
# set of options to run with
options=""
 
# default directory for screen, needs to be an absolute path
base="/home/@USER@"
 
# name of screen session
srnname="rtorrent"
 
# file to log to (makes for easier debugging if something goes wrong)
logfile="/var/log/rtorrentInit.log"
#######################
###END CONFIGURATION###
#######################
PATH=/usr/bin:/usr/local/bin:/usr/local/sbin:/sbin:/bin:/usr/sbin
DESC="rtorrent"
NAME=rtorrent
DAEMON=$NAME
SCRIPTNAME=/etc/init.d/$NAME
 
checkcnfg() {
    exists=0
    for i in `echo "$PATH" | tr ':' '\n'` ; do
        if [ -f $i/$NAME ] ; then
            exists=1
            break
        fi
    done
    if [ $exists -eq 0 ] ; then
        echo "cannot find rtorrent binary in PATH $PATH" | tee -a "$logfile" >&2
        exit 3
    fi
    if ! [ -r "${config}" ] ; then
        echo "cannot find readable config ${config}. check that it is there and permissions are appropriate" | tee -a "$logfile" >&2
        exit 3
    fi
    session=`getsession "$config"`
    if ! [ -d "${session}" ] ; then
        echo "cannot find readable session directory ${session} from config ${config}. check permissions" | tee -a "$logfile" >&2
        exit 3
 
        fi
 
}
 
d_start() {
 
  [ -d "${base}" ] && cd "${base}"
 
  stty stop undef && stty start undef
  su -c "screen -ls | grep -sq "\.${srnname}[[:space:]]" " ${user} || su -c "screen -dm -S ${srnname} 2>&1 1>/dev/null" ${user} | tee -a "$logfile" >&2
  su -c "screen -S "${srnname}" -X screen rtorrent ${options} 2>&1 1>/dev/null" ${user} | tee -a "$logfile" >&2
}
 
d_stop() {
    session=`getsession "$config"`
    if ! [ -s ${session}/rtorrent.lock ] ; then
        return
    fi
    pid=`cat ${session}/rtorrent.lock | awk -F: '{print($2)}' | sed "s/[^0-9]//g"`
    if ps -A | grep -sq ${pid}.*rtorrent ; then # make sure the pid doesn't belong to another process
        kill -s INT ${pid}
    fi
}
 
getsession() {
    session=`cat "$1" | grep "^[[:space:]]*session[[:space:]]*=" | sed "s/^[[:space:]]*session[[:space:]]*=[[:space:]]*//" `
    echo $session
}
 
checkcnfg
 
case "$1" in
  start)
    echo -n "Starting $DESC: $NAME"
    d_start
    echo "."
    ;;
  stop)
    echo -n "Stopping $DESC: $NAME"
    d_stop
    echo "."
    ;;
  restart|force-reload)
    echo -n "Restarting $DESC: $NAME"
    d_stop
    sleep 1
    d_start
    echo "."
    ;;
  *)
    echo "Usage: $SCRIPTNAME {start|stop|restart|force-reload}" >&2
    exit 1
    ;;
esac
 
exit 0
EOF

sed -i "s/@USER@/$USER/g;" /etc/init.d/$USER-rtorrent
chmod +x /etc/init.d/$USER-rtorrent

# crontab
crontab -l > rtorrentdem
echo "* * * * * if ! ( ps -U $USER | grep rtorrent > /dev/null ); then /etc/init.d/$USER-rtorrent start; fi > /dev/null 2>&1" >> rtorrentdem
crontab rtorrentdem
rm rtorrentdem

service $USER-rtorrent restart

# htpasswd
htpasswd -bs /etc/nginx/passwd/rutorrent_passwd $USER ${PASSNGINX}
htpasswd -cbs /etc/nginx/passwd/rutorrent_passwd_$USER $USER ${PASSNGINX}
chmod 640 /etc/nginx/passwd/*
chown -c www-data:www-data /etc/nginx/passwd/*
service nginx restart

# seedbox-manager conf user
cd /var/www/seedbox-manager/conf/users/
mkdir $USER

cat <<'EOF' >  /var/www/seedbox-manager/conf/users/$USER/config.ini
; Manager de seedbox (adapté pour le tuto de lufki.org)
;
; Fichier de configuration :
; yes ou no pour activer les modules
; Si vous n'avez pas de nom de domaine, indiquez l'ip (ex: http://XX.XX.XX.XX/rutorrent)

[user]
active_bloc_info = yes
user_directory = "/home/mannix/"
scgi_folder = "/RPC1"
theme = "Oblivion"
owner = no

[nav]
data_link = "url = https://lufki.org/rutorrent, name = rutorrent
url = https://proxy.lufki.org, name = proxy
url = https://graph.lufki.org, name = graph"

[ftp]
active_ftp = yes
port_ftp = "21"
port_sftp = "22"

[rtorrent]
active_reboot = yes

[support]
active_support = yes
adresse_mail = "wtf@lufki.org"

[logout]
url_redirect = "http://cakebox.lufki.org"

EOF
sed -i "s/\"\/\"/\"\/home\/$USER\"/g;" /var/www/seedbox-manager/conf/users/$USER/config.ini
sed -i "s/rutorrent.lufki.org/$IP\/rutorrent\//g;" /var/www/seedbox-manager/conf/users/$USER/config.ini
sed -i "s/proxy.lufki.org/$IP\/proxy\//g;" /var/www/seedbox-manager/conf/users/$USER/config.ini
sed -i "s/graph.lufki.org/$IP\/graph\/$USER.php/g;" /var/www/seedbox-manager/conf/users/$USER/config.ini
sed -i "s/RPC1/$USERMAJ/g;" /var/www/seedbox-manager/conf/users/$USER/config.ini
sed -i "s/darwinsblade@gmail.com/$EMAIL/g;" /var/www/seedbox-manager/conf/users/$USER/config.ini

chown -R www-data:www-data /var/www/seedbox-manager/conf/users/

# configuration page index munin
if [ ! -f /var/www/monitoring/localdomain/index.html ]; then
	MUNINROUTE=$"locahost/localhost"
else
	MUNINROUTE=$"localdomain/localhost.localdomain"
fi

ln -s /var/www/monitoring/"$MUNINROUTE"/rtom_"$USER"_mem-day.png /var/www/graph/img/rtom_"$USER"_mem-day.png
ln -s /var/www/monitoring/"$MUNINROUTE"/rtom_"$USER"_mem-week.png /var/www/graph/img/rtom_"$USER"_mem-week.png
ln -s /var/www/monitoring/"$MUNINROUTE"/rtom_"$USER"_mem-month.png /var/www/graph/img/rtom_"$USER"_mem-month.png

ln -s /var/www/monitoring/"$MUNINROUTE"/rtom_"$USER"_peers-day.png /var/www/graph/img/rtom_"$USER"_peers-day.png
ln -s /var/www/monitoring/"$MUNINROUTE"/rtom_"$USER"_peers-week.png /var/www/graph/img/rtom_"$USER"_peers-week.png
ln -s /var/www/monitoring/"$MUNINROUTE"/rtom_"$USER"_peers-month.png /var/www/graph/img/rtom_"$USER"_peers-month.png

ln -s /var/www/monitoring/"$MUNINROUTE"/rtom_"$USER"_spdd-day.png /var/www/graph/img/rtom_"$USER"_spdd-day.png
ln -s /var/www/monitoring/"$MUNINROUTE"/rtom_"$USER"_spdd-week.png /var/www/graph/img/rtom_"$USER"_spdd-week.png
ln -s /var/www/monitoring/"$MUNINROUTE"/rtom_"$USER"_spdd-month.png /var/www/graph/img/rtom_"$USER"_spdd-month.png

ln -s /var/www/monitoring/"$MUNINROUTE"/rtom_"$USER"_vol-day.png /var/www/graph/img/rtom_"$USER"_vol-day.png
ln -s /var/www/monitoring/"$MUNINROUTE"/rtom_"$USER"_vol-week.png /var/www/graph/img/rtom_"$USER"_vol-week.png
ln -s /var/www/monitoring/"$MUNINROUTE"/rtom_"$USER"_vol-month.png /var/www/graph/img/rtom_"$USER"_vol-month.png

cp /var/www/graph/user.php /var/www/graph/$USER.php

sed -i "s/@USER@/$USER/g;" /var/www/graph/$USER.php
sed -i "s/@USERROUTE@/$IP\/graph\/img/g;" /var/www/graph/$USER.php
sed -i "s/@RTOM@/rtom_$USER/g;" /var/www/graph/$USER.php
sed -i "s/@MANAGER@/$IP\/seedbox-manager\//g;" /var/www/graph/$USER.php
sed -i "s/@RUTORRENT@/$IP\/rutorrent\//g;" /var/www/graph/$USER.php

chown -R www-data:www-data /var/www/graph

# log users
echo "userlog">> /var/www/rutorrent/histo.log
sed -i "s/userlog/$USER:$PORT/g;" /var/www/rutorrent/histo.log

echo "" 
echo -e "${CBLUE}Ajout de l'utilisateur terminé !$CEND"

echo ""
echo -e "${CGREEN}Gardez bien ces informations:$CEND"
echo -e "${CBLUE}Username: $CEND${CYELLOW}$USER$CEND"
echo -e "${CBLUE}Password: $CEND${CYELLOW}${PASSNGINX}$CEND"
echo -e "${CGREEN}Elles vous permettront de vous connecter sur ruTorrent,\nSeedbox-Manager et en FTP si vous possédez cette option.$CEND"
echo ""
;;

# suspendre utilisateur
2)

echo ""
echo -n -e "${CGREEN}Entrez le nom de l'utilisateur (en minuscule): $CEND"
read USER

# variable email (rétro compatible)
TESTMAIL=$(sed -n "1 p" /var/www/rutorrent/histo.log)
IFS="@"
set -- $TESTMAIL
if [ "${#@}" -ne 2 ];then
    EMAIL=contact@exemple.com
else
    EMAIL=$TESTMAIL
fi

# récupération IP serveur
IP=$(ifconfig | grep 'inet addr:' | grep -v inet6 | grep -vE '127\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | cut -d: -f2 | awk '{ print $1}' | head -1)
if [ "$IP" = "" ]; then
	IP=$(wget -qO- ipv4.icanhazip.com)
fi

# variable utilisateur majuscule
USERMAJ=`echo $USER | tr "[:lower:]" "[:upper:]"`

echo ""
echo -e "${CBLUE}Suspension de l'utilisateur.$CEND"
echo ""

# crontab
crontab -l > /tmp/rmuser
sed -i "s/* \* \* \* \* if ! ( ps -U $USER | grep rtorrent > \/dev\/null ); then \/etc\/init.d\/$USER-rtorrent start; fi > \/dev\/null 2>&1//g;" /tmp/rmuser
crontab /tmp/rmuser
rm /tmp/rmuser

# contrôle présence utilitaire
if [ ! -f /var/www/base/aide/contact.html ]; then
	cd /tmp
	wget http://www.bonobox.net/script/contact.tar.gz
	tar xzfv contact.tar.gz
	cp /tmp/contact/contact.html /var/www/base/aide/contact.html
	cp /tmp/contact/style/style.css /var/www/base/aide/style/style.css
fi

#  page support
cp /var/www/base/aide/contact.html /var/www/base/$USER.html
sed -i "s/@USER@/$USER/g;" /var/www/base/$USER.html
chown -R www-data:www-data /var/www/base/$USER.html

# Seedbox-Manager service minimum
mv /var/www/seedbox-manager/conf/users/$USER/config.ini /var/www/seedbox-manager/conf/users/$USER/config.bak

cat <<'EOF' >  /var/www/seedbox-manager/conf/users/$USER/config.ini
; Manager de seedbox (adapté pour le tuto de lufki.org)
;
; Fichier de configuration :
; yes ou no pour activer les modules
; Si vous n'avez pas de nom de domaine, indiquez l'ip (ex: http://XX.XX.XX.XX/rutorrent)

[user]
active_bloc_info = yes
user_directory = "/home/mannix/"
scgi_folder = "/RPC1"
theme = "Oblivion"
owner = no

[nav]
data_link = "url = https://lufki.org/rutorrent, name = rutorrent
url = https://proxy.lufki.org, name = proxy"

[ftp]
active_ftp = yes
port_ftp = "21"
port_sftp = "22"

[rtorrent]
active_reboot = yes

[support]
active_support = yes
adresse_mail = "wtf@lufki.org"

[logout]
url_redirect = "http://cakebox.lufki.org"

EOF
sed -i "s/\"\/\"/\"\/home\/$USER\"/g;" /var/www/seedbox-manager/conf/users/$USER/config.ini
sed -i "s/rutorrent.lufki.org/$IP\/$USER.html/g;" /var/www/seedbox-manager/conf/users/$USER/config.ini
sed -i "s/proxy.lufki.org/$IP\/$USER.html/g;" /var/www/seedbox-manager/conf/users/$USER/config.ini
sed -i "s/lufki.org/$IP\/$USER.html/g;" /var/www/seedbox-manager/conf/users/$USER/config.ini
sed -i "s/RPC1/$USERMAJ/g;" /var/www/seedbox-manager/conf/users/$USER/config.ini
sed -i "s/wtf@lufki.org/$EMAIL/g;" /var/www/seedbox-manager/conf/users/$USER/config.ini

chown -R www-data:www-data /var/www/seedbox-manager/conf/users/

# stop user
/etc/init.d/$USER-rtorrent stop
killall --user $USER rtorrent
killall --user $USER screen

usermod -L $USER

echo ""
echo -e "${CBLUE}L'utilisateur$CEND ${CYELLOW}$USER$CEND ${CBLUE}a bien été suspendu.$CEND"
;;

# rétablir utilisateur
3)

echo ""
echo -n -e "${CGREEN}Entrez le nom de l'utilisateur (en minuscule): $CEND"
read USER
echo ""
echo -e "${CBLUE}Rétablissement de l'utilisateur.$CEND"
echo ""

# crontab
crontab -l > rtorrentdem
echo "* * * * * if ! ( ps -U $USER | grep rtorrent > /dev/null ); then /etc/init.d/$USER-rtorrent start; fi > /dev/null 2>&1" >> rtorrentdem
crontab rtorrentdem
rm rtorrentdem

# start user
service $USER-rtorrent start
usermod -U $USER

# Seedbox-Manager service normal
rm /var/www/seedbox-manager/conf/users/$USER/config.ini
mv /var/www/seedbox-manager/conf/users/$USER/config.bak /var/www/seedbox-manager/conf/users/$USER/config.ini
chown -R www-data:www-data /var/www/seedbox-manager/conf/users/
rm /var/www/base/$USER.html

echo ""
echo -e "${CBLUE}L'utilisateur$CEND ${CYELLOW}$USER$CEND ${CBLUE}a bien été rétabli.$CEND"
;;

# modification mot de passe utilisateur
4)

echo ""
echo -n -e "${CGREEN}Entrez le nom de l'utilisateur (en minuscule): $CEND"
read USER
echo ""
echo -e "${CGREEN}Entrez le nouveau mot de passe pour cet utilisateur,\nou appuyez sur \"$CEND${CYELLOW}Entrée$CEND${CGREEN}\" pour en générer un automatiquement: $CEND"
read REPPWD
if [ "$REPPWD" = "" ]; then
    while :; do
    AUTOPWD=$(strings /dev/urandom | grep -o '[1-9A-NP-Za-np-z]' | head -n 8 | tr -d '\n')
    echo -e -n "${CGREEN}Voulez vous utiliser$CEND ${CYELLOW}$AUTOPWD$CEND${CGREEN} comme mot de passe ? (y/n] : $CEND"
        read REPONSEPWD
        if [ "$REPONSEPWD" = "n" ]; then
            echo
        else
           PWD=$AUTOPWD
           break

       fi
    done
else
    PWD=$REPPWD
fi
echo ""
echo -e "${CBLUE}Modification du mot de passe de l'utilisateur.$CEND"
echo ""

# variable passe nginx
PASSNGINX=${PWD}
echo ""

# modification du mot de passe pour cet utilisateur
echo "${USER}:${PWD}" | chpasswd

# htpasswd
htpasswd -bs /etc/nginx/passwd/rutorrent_passwd $USER ${PASSNGINX}
htpasswd -cbs /etc/nginx/passwd/rutorrent_passwd_$USER $USER ${PASSNGINX}
chmod 640 /etc/nginx/passwd/*
chown -c www-data:www-data /etc/nginx/passwd/*
service nginx restart

echo ""
echo -e "${CBLUE}Le mot de passe utilisateur de$CEND ${CYELLOW}$USER$CEND ${CBLUE}a bien été modifié.$CEND"
echo
echo -e "${CGREEN}Gardez bien ces informations:$CEND"
echo -e "${CBLUE}Username: $CEND${CYELLOW}$USER$CEND"
echo -e "${CBLUE}Password: $CEND${CYELLOW}${PASSNGINX}$CEND"
echo -e "${CGREEN}Elles vous permettront de vous connecter sur ruTorrent,\nSeedbox-Manager et en FTP si vous possédez cette option.$CEND"
echo ""
;;

# suppression utilisateur
5)

echo ""
echo -n -e "${CGREEN}Entrez le nom de l'utilisateur (en minuscule): $CEND"
read USER
echo ""
echo -e "${CBLUE}Suppression de l'utilisateur.$CEND"
echo ""

# variable utilisateur majuscule
USERMAJ=`echo $USER | tr "[:lower:]" "[:upper:]"`
echo -e "$USERMAJ"

# suppression conf munin
rm /var/www/graph/img/rtom_"$USER"_*
rm /var/www/graph/$USER.php

sed -i '/rtom_'$USER'_peers.graph_width 700/,+8d' /etc/munin/munin.conf
sed -i '/\[rtom_'$USER'_\*\]/,+6d' /etc/munin/plugin-conf.d/munin-node

rm /etc/munin/plugins/rtom_"$USER"_*
#rm /etc/munin/plugins/rtom_"$USER"_mem
#rm /etc/munin/plugins/rtom_"$USER"_peers
#rm /etc/munin/plugins/rtom_"$USER"_spdd
#rm /etc/munin/plugins/rtom_"$USER"_vol

rm /usr/share/munin/plugins/rtom_"$USER"_*
#rm /usr/share/munin/plugins/rtom_"$USER"_mem
#rm /usr/share/munin/plugins/rtom_"$USER"_peers
#rm /usr/share/munin/plugins/rtom_"$USER"_spdd
#rm /usr/share/munin/plugins/rtom_"$USER"_vol

/etc/init.d/munin-node restart

# crontab
crontab -l > /tmp/rmuser
sed -i "s/* \* \* \* \* if ! ( ps -U $USER | grep rtorrent > \/dev\/null ); then \/etc\/init.d\/$USER-rtorrent start; fi > \/dev\/null 2>&1//g;" /tmp/rmuser
crontab /tmp/rmuser
rm /tmp/rmuser

# stop user
/etc/init.d/$USER-rtorrent stop
killall --user $USER rtorrent
killall --user $USER screen

# suppression script
rm /etc/init.d/$USER-rtorrent

# suppression conf rutorrent
rm -R /var/www/rutorrent/conf/users/$USER
rm -R /var/www/rutorrent/share/users/$USER

# suppression pass
sed -i "/^$USER/d" /etc/nginx/passwd/rutorrent_passwd
rm /etc/nginx/passwd/rutorrent_passwd_$USER

# suppression nginx
sed -i '/location \/'"$USERMAJ"'/,/}/d' /etc/nginx/sites-enabled/rutorrent.conf
service nginx restart

# suppression seebbox-manager
rm -R /var/www/seedbox-manager/conf/users/$USER

# suppression user
deluser $USER --remove-home

echo ""
echo -e "${CBLUE}L'utilisateur$CEND ${CYELLOW}$USER$CEND ${CBLUE}a bien été supprimé.$CEND"
;;

# sortir gestion utilisateurs
6)
echo ""
echo -n -e "${CGREEN}Voulez vous redémarrer pour finaliser la gestion utilisateur (y/n): $CEND"
read REBOOT

if [ "$REBOOT" = "n" ]; then
	echo ""
	echo -e "${CRED}Penser à redémarrer manuellement votre serveur avant utilisation !$CEND"
	echo ""

	echo ""
	exit 1
fi

if [ "$REBOOT" = "y" ]; then
	echo ""					

	echo ""
	reboot
fi

break
;;

*)
echo -e $CRED"Option invalide"$CEND
;;
esac
done
fi
fi
