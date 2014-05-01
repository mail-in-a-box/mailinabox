function apt_install {
	# Report any packages already installed.
	PACKAGES=$@
	TO_INSTALL=""
	for pkg in $PACKAGES; do
		if dpkg -s $pkg 2>/dev/null | grep "^Status: install ok installed" > /dev/null; then
			echo $pkg is already installed \(`dpkg -s $pkg | grep ^Version: | sed -e "s/.*: //"`\)
		else
			TO_INSTALL="$TO_INSTALL""$pkg "
		fi
	done

	# List the packages about to be installed.
	if [[ ! -z "$TO_INSTALL" ]]; then
		echo installing $TO_INSTALL...
	fi

	# 'DEBIAN_FRONTEND=noninteractive' is to prevent dbconfig-common from asking you questions.
	DEBIAN_FRONTEND=noninteractive apt-get -qq -y install $PACKAGES > /dev/null;
}

