FROM ubuntu:16.04

# install apache, shibd and java
RUN apt update -y \
	&& apt install -y shibboleth-sp2-common libapache2-mod-shib2 apache2 shibboleth-sp2-utils openjdk-8-jdk gradle curl \
	&& apt clean


# It's not allowed to run services with root privileges in OpenShift at the moment. 
# We have to make some adjustments to allow Apache and shibd to run as a regular user. 
# The OpenShift will create a new user (with high UID) for running these services and 
# adds that user a group ´root´, so it's enough to give necessary permissions for that group.

# By default Apache tries to bind to port 80, which isn't allowed for normal users. Let's 
# disable that by replacing the  file with an empty file. We'll add a new minimal 
# configuration file to ´sites-enabled´ to be able to test that Apache starts. It will be 
# overridden by the real configuration later.

RUN chgrp -R root /var/log/apache2/ /var/lock/apache2/ /var/run/apache2/ \
	&& chmod -R g+w /var/log/apache2/ /var/lock/apache2/ /var/run/apache2/ \
	&& mv /etc/apache2/ports.conf /etc/apache2/ports.conf.original \
	&& echo "Listen 8000" > /etc/apache2/sites-enabled/shibboleth.conf \
	&& touch /etc/apache2/ports.conf
	
		
# We are going to configure the Apache and shibd by mounting a new directtory (called 
# *secret* in OpenShift) containing the configuration files. For Apache we can simply mount 
# it to ´/etc/apache2/sites-enabled´, where Apache will automatically look for all files 
# ending with ´.conf´. On the contrary, shibd has a lot of configuration files in the same 
# directory and we want to replace only some of them, so we can't simply replace the whole 
# directory. Instead we create a new directory ´/etc/shibboleth/secret´ and replace the 
# relevant configuration files with a symlink pointing to that directory. The default 
# `shibbleth2.xml´ is copied to the folder ´secret´ so that we can test that the *shibd* 
# starts even before we have configured it.

# Also shibd expects rights to write in a few directories under ´/var´ like Apache. 
	 	
RUN mkdir /etc/shibboleth/secret \
	&& cd /etc/shibboleth \
	&& cp shibboleth2.xml secret/shibboleth2.xml \
	&& mv shibboleth2.xml shibboleth2.xml.original \
	&& mv attribute-map.xml attribute-map.xml.original \
	&& ln -s secret/shibboleth2.xml shibboleth2.xml \
	&& ln -s secret/attribute-map.xml attribute-map.xml \
	&& mkdir -p /var/run/shibboleth /var/cache/shibboleth /var/log/shibboleth \
	&& chgrp -R root /var/run/shibboleth /var/cache/shibboleth /var/log/shibboleth \
	&& chmod -R g+w /var/run/shibboleth /var/cache/shibboleth /var/log/shibboleth


# Set the command for starting services. Usually each process should be in its own container, 
# but these pocesses were made to run in the same machine. Starting two processes like this 
# won't handle the shutdown signals correctly (´exec´ fixes it only for one process), so your 
# login requests may fail during the deployments. If you try to fix this with a process manager 
# like *supervisord*, be warned that the shibd process saves same state about the login session, 
# which probably has to sorted out also to get error-free rolling updates.

CMD ["bash", "-c", "/etc/init.d/apache2 start; shibd -F start"]