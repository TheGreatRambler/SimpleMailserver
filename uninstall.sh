#!/bin/bash

if [[ $(id -u) -ne 0 ]]; then
	echo "This script requires root (sudo) to modify packages"
	exit 1
fi

while :
do
	# Read variables before starting
	read -ep "Enter domain name used during install: " DOMAIN_NAME
	if [[ -z "$DOMAIN_NAME" ]]; then
		echo "Please enter domain name"
		continue
	fi

	read -ep "Enter mail subdomain used during install (mail.${DOMAIN_NAME}): " MAIL_SUBDOMAIN \
		&& [[ -z "$MAIL_SUBDOMAIN" ]] && MAIL_SUBDOMAIN="mail.${DOMAIN_NAME}"

	SETTINGS_CONFIRM="Chosen settings:
	Domain: ${DOMAIN_NAME},
	Mail subdomain: ${MAIL_SUBDOMAIN}
Is this ok [y/n]? "
	# Prompt user for these settings and continue if ok
	read -ep "$SETTINGS_CONFIRM" SETTINGS_OK

	if [[ $SETTINGS_OK == "y" || $SETTINGS_OK == "Y" ]]; then
		break
	fi
done

# Uninstall key packages
echo "----- Uninstalling packages -----"
systemctl stop postfix > /dev/null
systemctl stop dovecot > /dev/null
apt-get purge postfix libsasl2-modules -y > /dev/null
apt-get purge dovecot-core dovecot-imapd dovecot-pop3d > /dev/null

# Delete configuration files
echo "----- Delete configuration files -----"
rm /etc/postfix/master.cf
rm /etc/postfix/main.cf
rm /etc/postfix/sasl/sasl_passwd
rm /etc/postfix/sasl/sasl_passwd.db
rm /etc/dovecot/dovecot.conf

# Revert certain configs, certbot and UFW are common enough that the user
#     may have had them before running install.sh
echo "----- Revert certbot/UFW config -----"
sudo certbot delete --cert-name $MAIL_SUBDOMAIN > /dev/null
ufw deny Postfix > /dev/null
ufw deny "Dovecot IMAP" > /dev/null
ufw deny "Dovecot Secure IMAP" > /dev/null
ufw deny 465/tcp > /dev/null # SMTPS
ufw deny 995/tcp > /dev/null # POP3