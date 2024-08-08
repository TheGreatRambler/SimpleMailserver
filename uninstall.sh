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
systemctl stop postfix
systemctl stop dovecot
apt-get purge postfix libsasl2-modules -y
apt-get purge dovecot-core dovecot-imapd dovecot-pop3d

# Revert certain configs, certbot and UFW are common enough that the user
#     may have had them before running install.sh
echo "----- Revert certbot/UFW config -----"
yes | certbot delete --non-interactive --cert-name $MAIL_SUBDOMAIN
ufw deny Postfix
ufw deny "Postfix SMTPS"
ufw deny "Postfix Submission"
ufw deny "Dovecot IMAP"
ufw deny "Dovecot Secure IMAP"