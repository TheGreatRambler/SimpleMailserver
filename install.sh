#!/bin/bash

if [[ $(id -u) -ne 0 ]]; then
	echo "This script requires root (sudo) to install packages"
	exit 1
fi

while :
do
	# Read variables before starting
	read -ep "Enter domain name: " DOMAIN_NAME
	if [[ -z "$DOMAIN_NAME" ]]; then
		echo "Please enter domain name"
		continue
	fi

	read -ep "Enter mail subdomain (mail.${DOMAIN_NAME}): " MAIL_SUBDOMAIN \
		&& [[ -z "$MAIL_SUBDOMAIN" ]] && MAIL_SUBDOMAIN="mail.${DOMAIN_NAME}"

	read -ep "Enter admin user, must be existing user: " ADMIN_USER
	if [[ -z "$ADMIN_USER" || $(id -u $ADMIN_USER > /dev/null 2>&1 ; echo $?) -ne 0 ]]; then
		echo "Please enter valid user"
		continue
	fi

	read -ep "Enter certbot email (${ADMIN_USER}@${DOMAIN_NAME}): " CERTBOT_EMAIL \
		&& [[ -z "$CERTBOT_EMAIL" ]] && CERTBOT_EMAIL="${ADMIN_USER}@${DOMAIN_NAME}"

	read -ep "Enter Gmail email for relay: " GOOGLE_EMAIL
	if [[ -z "$GOOGLE_EMAIL" ]]; then
		echo "Please enter Gmail email"
		continue
	fi

	read -ep "Enter Google app password for relay: " APP_PASSWORD
	if [[ -z "$APP_PASSWORD" ]]; then
		echo "Please enter Google app password"
		continue
	fi

	SETTINGS_CONFIRM="Chosen settings:
	Domain: ${DOMAIN_NAME},
	Mail subdomain: ${MAIL_SUBDOMAIN},
	Admin email: ${ADMIN_USER}@${DOMAIN_NAME}
	Certbot email: ${CERTBOT_EMAIL}
	Gmail email: ${GOOGLE_EMAIL}
	App password: ${APP_PASSWORD}
Is this ok [y/n]? "
	# Prompt user for these settings and continue if ok
	read -ep "$SETTINGS_CONFIRM" SETTINGS_OK

	if [[ $SETTINGS_OK == "y" || $SETTINGS_OK == "Y" ]]; then
		break
	fi
done

# Update package repositories
echo "----- Updating package repositories -----"
apt-get update > /dev/null
apt-get upgrade > /dev/null
# Install UFW (firewall)
echo "----- Installing UFW -----"
apt-get install ufw -y > /dev/null
# Install certbot, involved configuration
echo "----- Installing certbot -----"
apt-get install snapd -y > /dev/null
snap install core > /dev/null
snap install --classic certbot > /dev/null
ln -s /snap/bin/certbot /usr/bin/certbot > /dev/null

# Create certificate
echo "----- Creating SSL certificate -----"
#sudo certbot certonly --standalone --non-interactive --domains $MAIL_SUBDOMAIN --agree-tos -m $CERTBOT_EMAIL > /dev/null
#if [[ $? -ne 0 ]]; then
#	echo "Certbot failed, check that you have AAAA records for ${MAIL_SUBDOMAIN}"
#	exit 1
#fi

# Install postfix
echo "----- Installing postfix -----"
apt-get remove exim4 > /dev/null
debconf-set-selections <<< "postfix postfix/mailname string ${DOMAIN_NAME}"
debconf-set-selections <<< "postfix postfix/main_mailer_type string 'Internet Site'"
apt-get install postfix libsasl2-modules -y > /dev/null
systemctl stop postfix > /dev/null

# Change postfix master.cf and main.cf configurations
echo "----- Creating configuration files -----"
MASTER_CF_CONTENTS="#
# Postfix master process configuration file.  For details on the format
# of the file, see the master(5) manual page (command: \"man 5 master\" or
# on-line: http://www.postfix.org/master.5.html).
#
# Do not forget to execute \"postfix reload\" after editing this file.
#
# ==========================================================================
# service type  private unpriv  chroot  wakeup  maxproc command + args
#               (yes)   (yes)   (no)    (never) (100)
# ==========================================================================
smtp      inet  n       -       y       -       -       smtpd
#smtp      inet  n       -       y       -       1       postscreen
#smtpd     pass  -       -       y       -       -       smtpd
#dnsblog   unix  -       -       y       -       0       dnsblog
#tlsproxy  unix  -       -       y       -       0       tlsproxy
submission inet n       -       y       -       -       smtpd
  -o syslog_name=postfix/submission
  -o smtpd_tls_security_level=encrypt
  -o smtpd_sasl_auth_enable=yes
  -o smtpd_tls_auth_only=yes
  -o smtpd_reject_unlisted_recipient=no
  -o smtpd_client_restrictions=\$mua_client_restrictions
  -o smtpd_helo_restrictions=\$mua_helo_restrictions
  -o smtpd_sender_restrictions=\$mua_sender_restrictions
  -o smtpd_recipient_restrictions=
  -o smtpd_relay_restrictions=permit_sasl_authenticated,reject
  -o milter_macro_daemon_name=ORIGINATING
smtps     inet  n       -       y       -       -       smtpd
  -o syslog_name=postfix/smtps
  -o smtpd_tls_wrappermode=yes
  -o smtpd_sasl_auth_enable=yes
  -o smtpd_reject_unlisted_recipient=no
  -o smtpd_client_restrictions=\$mua_client_restrictions
  -o smtpd_helo_restrictions=\$mua_helo_restrictions
  -o smtpd_sender_restrictions=\$mua_sender_restrictions
  -o smtpd_recipient_restrictions=
  -o smtpd_relay_restrictions=permit_sasl_authenticated,reject
  -o milter_macro_daemon_name=ORIGINATING
#628       inet  n       -       y       -       -       qmqpd
pickup    unix  n       -       y       60      1       pickup
cleanup   unix  n       -       y       -       0       cleanup
qmgr      unix  n       -       n       300     1       qmgr
#qmgr     unix  n       -       n       300     1       oqmgr
tlsmgr    unix  -       -       y       1000?   1       tlsmgr
rewrite   unix  -       -       y       -       -       trivial-rewrite
bounce    unix  -       -       y       -       0       bounce
defer     unix  -       -       y       -       0       bounce
trace     unix  -       -       y       -       0       bounce
verify    unix  -       -       y       -       1       verify
flush     unix  n       -       y       1000?   0       flush
proxymap  unix  -       -       n       -       -       proxymap
proxywrite unix -       -       n       -       1       proxymap
smtp      unix  -       -       y       -       -       smtp
relay     unix  -       -       y       -       -       smtp
        -o syslog_name=postfix/\$service_name
#       -o smtp_helo_timeout=5 -o smtp_connect_timeout=5
showq     unix  n       -       y       -       -       showq
error     unix  -       -       y       -       -       error
retry     unix  -       -       y       -       -       error
discard   unix  -       -       y       -       -       discard
local     unix  -       n       n       -       -       local
virtual   unix  -       n       n       -       -       virtual
lmtp      unix  -       -       y       -       -       lmtp
anvil     unix  -       -       y       -       1       anvil
scache    unix  -       -       y       -       1       scache
postlog   unix-dgram n  -       n       -       1       postlogd
#
# ====================================================================
# Interfaces to non-Postfix software. Be sure to examine the manual
# pages of the non-Postfix software to find out what options it wants.
#
# Many of the following services use the Postfix pipe(8) delivery
# agent.  See the pipe(8) man page for information about \${recipient}
# and other message envelope options.
# ====================================================================
#
# maildrop. See the Postfix MAILDROP_README file for details.
# Also specify in main.cf: maildrop_destination_recipient_limit=1
#
maildrop  unix  -       n       n       -       -       pipe
  flags=DRXhu user=vmail argv=/usr/bin/maildrop -d \${recipient}
#
# ====================================================================
#
# Recent Cyrus versions can use the existing \"lmtp\" master.cf entry.
#
# Specify in cyrus.conf:
#   lmtp    cmd=\"lmtpd -a\" listen=\"localhost:lmtp\" proto=tcp4
#
# Specify in main.cf one or more of the following:
#  mailbox_transport = lmtp:inet:localhost
#  virtual_transport = lmtp:inet:localhost
#
# ====================================================================
#
# Cyrus 2.1.5 (Amos Gouaux)
# Also specify in main.cf: cyrus_destination_recipient_limit=1
#
#cyrus     unix  -       n       n       -       -       pipe
#  flags=DRX user=cyrus argv=/cyrus/bin/deliver -e -r \${sender} -m \${extension} \${user}
#
# ====================================================================
# Old example of delivery via Cyrus.
#
#old-cyrus unix  -       n       n       -       -       pipe
#  flags=R user=cyrus argv=/cyrus/bin/deliver -e -m \${extension} \${user}
#
# ====================================================================
#
# See the Postfix UUCP_README file for configuration details.
#
uucp      unix  -       n       n       -       -       pipe
  flags=Fqhu user=uucp argv=uux -r -n -z -a\$sender - \$nexthop!rmail (\$recipient)
#
# Other external delivery methods.
#
ifmail    unix  -       n       n       -       -       pipe
  flags=F user=ftn argv=/usr/lib/ifmail/ifmail -r \$nexthop (\$recipient)
bsmtp     unix  -       n       n       -       -       pipe
  flags=Fq. user=bsmtp argv=/usr/lib/bsmtp/bsmtp -t\$nexthop -f\$sender \$recipient
scalemail-backend unix -       n       n       -       2       pipe
  flags=R user=scalemail argv=/usr/lib/scalemail/bin/scalemail-store \${nexthop} \${user} \${extension}
mailman   unix  -       n       n       -       -       pipe
  flags=FRX user=list argv=/usr/lib/mailman/bin/postfix-to-mailman.py \${nexthop} \${user}
"
echo "$MASTER_CF_CONTENTS" > /etc/postfix/master.cf

MAIN_CF_CONTENTS="
# See /usr/share/postfix/main.cf.dist for a commented, more complete version

# Debian specific:  Specifying a file name will cause the first
# line of that file to be used as the name.  The Debian default
# is /etc/mailname.
#myorigin = /etc/mailname

smtpd_banner = \$myhostname ESMTP \$mail_name (Debian/GNU)
biff = no

# appending .domain is the MUA's job.
append_dot_mydomain = no

# Uncomment the next line to generate \"delayed mail\" warnings
#delay_warning_time = 4h

readme_directory = no

# See http://www.postfix.org/COMPATIBILITY_README.html -- default to 2 on
# fresh installs.
compatibility_level = 2

# TLS parameters
smtpd_tls_cert_file=/etc/letsencrypt/live/$MAIL_SUBDOMAIN/fullchain.pem
smtpd_tls_key_file=/etc/letsencrypt/live/$MAIL_SUBDOMAIN/privkey.pem
smtpd_use_tls=yes
smtpd_tls_auth_only = yes
smtpd_tls_security_level=may
smtpd_tls_protocols = !SSLv2, !SSLv3

smtp_tls_CApath=/etc/ssl/certs
smtp_tls_security_level=may
smtp_tls_session_cache_database = btree:\${data_directory}/smtp_scache


smtpd_relay_restrictions = permit_mynetworks permit_sasl_authenticated defer_unauth_destination
myhostname = $MAIL_SUBDOMAIN
alias_maps = hash:/etc/aliases
alias_database = hash:/etc/aliases
myorigin = /etc/mailname
mydestination = \$myhostname, $DOMAIN_NAME, localhost, localhost.localdomain, localhost
relayhost = [smtp.gmail.com]:587
mynetworks = 127.0.0.0/8 [::ffff:127.0.0.0]/104 [::1]/128
mailbox_size_limit = 0
recipient_delimiter = +
inet_interfaces = all
inet_protocols = ipv4

smtpd_sasl_path = private/auth
smtpd_sasl_type = dovecot
smtpd_sasl_auth_enable = yes
smtpd_sasl_security_options = noanonymous
smtp_sasl_password_maps = hash:/etc/postfix/sasl/sasl_passwd
smtp_sasl_auth_enable = yes
smtp_sasl_security_options = noanonymous
smtp_use_tls = yes

local_recipient_maps = proxy:unix:passwd.byname $alias_maps
smtpd_restriction_classes = mua_sender_restrictions, mua_client_restrictions, mua_helo_restrictions
mua_client_restrictions = permit_sasl_authenticated, reject
mua_sender_restrictions = permit_sasl_authenticated, reject
mua_helo_restrictions = permit_mynetworks, reject_non_fqdn_hostname, reject_invalid_hostname, permit
"
echo "$MAIN_CF_CONTENTS" > /etc/postfix/main.cf

# Add aliases
ETC_ALIASES_CONTENTS="
mailer-daemon: postmaster
postmaster: root
nobody: root
hostmaster: root
usenet: root
news: root
webmaster: root
www: root
ftp: root
abuse: root
root: $ADMIN_USER
"
echo "$ETC_ALIASES_CONTENTS" > /etc/aliases
newaliases

# Add Google app password to access relay
SASL_PASSWORD_CONTENTS="
[smtp.gmail.com]:587     $GOOGLE_EMAIL:$APP_PASSWORD
"
echo "$SASL_PASSWORD_CONTENTS" > /etc/postfix/sasl/sasl_passwd
postmap /etc/postfix/sasl/sasl_passwd
chown root:root /etc/postfix/sasl/sasl_passwd /etc/postfix/sasl/sasl_passwd.db
chmod 0600 /etc/postfix/sasl/sasl_passwd /etc/postfix/sasl/sasl_passwd.db
rm /etc/postfix/sasl/sasl_passwd

# Install dovecot
echo "----- Installing dovecot -----"
apt-get install dovecot-core dovecot-imapd dovecot-pop3d > /dev/null
DOVECOT_CONF_CONTENTS="
disable_plaintext_auth = no
mail_privileged_group = mail
mail_location = mbox:~/mail:INBOX=/var/mail/%u
userdb {
  driver = passwd
}
passdb {
  args = %s
  driver = pam
}
protocols = \"imap pop3\"

service auth {
  unix_listener /var/spool/postfix/private/auth {
    group = postfix
    mode = 0660
    user = postfix
  }
}

ssl=required
ssl_cert = </etc/letsencrypt/live/$MAIL_SUBDOMAIN/fullchain.pem
ssl_key = </etc/letsencrypt/live/$MAIL_SUBDOMAIN/privkey.pem
"
echo "$DOVECOT_CONF_CONTENTS" > /etc/dovecot/dovecot.conf

# Verify hostname is set correctly, can conflict with mail
hostnamectl set-hostname $DOMAIN_NAME

# Open firewall
echo "----- Opening firewall -----"
ufw allow Postfix > /dev/null
ufw allow "Dovecot IMAP" > /dev/null
ufw allow "Dovecot Secure IMAP" > /dev/null
ufw allow 465/tcp > /dev/null # SMTPS
ufw allow 995/tcp > /dev/null # POP3

# Start services
echo "----- Starting services -----"
postfix start > /dev/null
service dovecot restart > /dev/null