if [[ $(id -u) -ne 0 ]] ; then
	echo "This script requires root (sudo) to install packages"
	exit 1
fi

while :
do
	# Read variables before starting
	read -ep "Enter domain name: " DOMAIN_NAME
	read -ep "Enter admin user, must be existing user: " ADMIN_USER
	read -ep "Enter mail subdomain (mail.${DOMAIN_NAME}): " MAIL_SUBDOMAIN
	SETTINGS_CONFIRM="Chosen settings:
    Domain: ${DOMAIN_NAME},
    Mail subdomain: ${MAIL_SUBDOMAIN},
    Admin email: ${ADMIN_USER}@${DOMAIN_NAME}
Is this ok [y/n]? 
	"
	# Prompt user for these settings and continue if ok
	read -ep $SETTINGS_CONFIRM SETTINGS_OK

	if [[ $SETTINGS_OK == "y" || $SETTINGS_OK == "Y"]] ; then
		break
	fi
done

# Update package repositories
sudo apt update
sudo apt upgrade
# Install required packages
sudo apt install ufw -y
# Install certbot, involved configuration
sudo apt install snapd -y
sudo snap install core
sudo snap install --classic certbot
sudo ln -s /snap/bin/certbot /usr/bin/certbot