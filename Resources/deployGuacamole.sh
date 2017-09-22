#!/bin/bash
#  Licensed under the Apache License, Version 2.0 (the "License"); you may
#  not use this file except in compliance with the License. You may obtain
#  a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
#  WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
#  License for the specific language governing permissions and limitations
#  under the License.

# Guacamole version
guac_version="0.9.13-incubating"
# Tomcat version
tcat_version=7

apt-get update

# Install Packages
debconf-set-selections <<< "mysql-server mysql-server/root_password password %PASSWORD%"
debconf-set-selections <<< "mysql-server mysql-server/root_password_again password %PASSWORD%"

apt-get -y install build-essential libcairo2-dev libjpeg-turbo8-dev libpng12-dev libossp-uuid-dev libavcodec-dev libavutil-dev \
  libswscale-dev libfreerdp-dev libpango1.0-dev libssh2-1-dev libtelnet-dev libvncserver-dev libpulse-dev libssl-dev \
  libvorbis-dev libwebp-dev mysql-server mysql-client mysql-common mysql-utilities freerdp ghostscript jq wget curl

# Download Guacamole Client
wget http://sourceforge.net/projects/guacamole/files/current/binary/guacamole-${guac_version}.war

# Download Guacamole Server
wget http://sourceforge.net/projects/guacamole/files/current/source/guacamole-server-${guac_version}.tar.gz

# Download Guacamole MySQL
wget https://downloads.sourceforge.net/project/guacamole/current/extensions/guacamole-auth-jdbc-${guac_version}.tar.gz

# Untar the guacamole server source files
tar -xzf guacamole-server-${guac_version}.tar.gz

# Configure MySQL
mkdir /etc/guacamole
mkdir /etc/guacamole/extensions
mkdir /etc/guacamole/lib
tar -xzf guacamole-auth-jdbc-${guac_version}.tar.gz
wget https://dev.mysql.com/get/Downloads/Connector-J/mysql-connector-java-5.1.41.tar.gz
tar -xzf mysql-connector-java-5.1.41.tar.gz
cp mysql-connector-java-5.1.41/mysql-connector-java-5.1.41-bin.jar /etc/guacamole/lib/
cp guacamole-auth-jdbc-${guac_version}/mysql/guacamole-auth-jdbc-mysql-${guac_version}.jar /etc/guacamole/extensions/

# Change directory to the source files
pushd guacamole-server-${guac_version}/
./configure --with-init-dir=/etc/init.d
make
make install
update-rc.d guacd defaults
ldconfig
popd

# Create guacamole configuration directory
echo "mysql-hostname: localhost" >> /etc/guacamole/guacamole.properties
echo "mysql-port: 3306" >> /etc/guacamole/guacamole.properties
echo "mysql-database: guacamole_db" >> /etc/guacamole/guacamole.properties
echo "mysql-username: guacamole_user" >> /etc/guacamole/guacamole.properties
echo "mysql-password: %PASSWORD%" >> /etc/guacamole/guacamole.properties

# Create a new user
useradd -d /etc/guacamole -p "$(openssl passwd -1 %PASSWORD%)" %USERNAME%
echo "guac ALL=(ALL) NOPASSWD:ALL" | tee /etc/sudoers.d/guac

# Enable SSH passwords
sed -i -e 's/PasswordAuthentication no/PasswordAuthentication yes/g' /etc/ssh/sshd_config
service sshd restart

# Create guacamole_db and grant guacamole_user permissions to it

MYCNF="[client]
user=root
host=localhost
password='%PASSWORD%'
socket=/var/run/mysqld/mysqld.sock
"

echo "$MYCNF" | tee /root/.my.cnf

# SQL Code
SQLCODE="
create database guacamole_db;
create user 'guacamole_user'@'localhost' identified by '%PASSWORD%';
GRANT SELECT,INSERT,UPDATE,DELETE ON guacamole_db.* TO 'guacamole_user'@'localhost';
flush privileges;"

# Execute SQL Code
echo "$SQLCODE" | mysql --defaults-extra-file=/root/.my.cnf

# Add Guacamole Schema to newly created database
cat guacamole-auth-jdbc-${guac_version}/mysql/schema/*.sql | mysql --defaults-extra-file=/root/.my.cnf guacamole_db

SQLCODE="
use guacamole_db;
SET @salt = UNHEX(SHA2(UUID(), 256));
update guacamole_user set username = '%USERNAME%', password_hash = UNHEX(SHA2(CONCAT('%PASSWORD%', HEX(@salt)), 256)), password_salt = @salt where user_id = 1;"
echo "$SQLCODE" | mysql --defaults-extra-file=/root/.my.cnf

# Make guacamole configuration directory readable and writable by the group and others
chmod -R go+rw /etc/guacamole
mkdir /usr/share/tomcat${tcat_version}/.guacamole

# Create a symbolic link of the properties file for Tomcat
ln -s /etc/guacamole/guacamole.properties /usr/share/tomcat${tcat_version}/.guacamole

# Copy the guacamole war file to the Tomcat webapps directory
cp guacamole-${guac_version}.war /var/lib/tomcat${tcat_version}/webapps/guacamole.war

# Start the Guacamole (guacd) service
service guacd start

# Set environment variable for tomcat
echo "GUACAMOLE_HOME=/etc/guacamole" >> /etc/default/tomcat${tcat_version}

# Restart Tomcat
service tomcat${tcat_version} restart
