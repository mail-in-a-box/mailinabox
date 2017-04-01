# If there aren't any mail users yet, create one.
if [ -z "`tools/mail.py user`" ]; then
	# The outut of "tools/mail.py user" is a list of mail users. If there
	# aren't any yet, it'll be empty.

	# If we didn't ask for an email address at the start, do so now.
	if [ -z "$EMAIL_ADDR" ]; then
		# In an interactive shell, ask the user for an email address.
		if [ -z "$NONINTERACTIVE" ]; then
			input_box "Mail Account" \
				"Let's create your first mail account.
				\n\nWhat email address do you want?" \
				me@`get_default_hostname` \
				EMAIL_ADDR

			if [ -z "$EMAIL_ADDR" ]; then
				# user hit ESC/cancel
				exit
			fi
			while ! management/mailconfig.py validate-email "$EMAIL_ADDR"
			do
				input_box "Mail Account" \
					"That's not a valid email address.
					\n\nWhat email address do you want?" \
					$EMAIL_ADDR \
					EMAIL_ADDR
				if [ -z "$EMAIL_ADDR" ]; then
					# user hit ESC/cancel
					exit
				fi
			done

		# But in a non-interactive shell, just make something up.
		# This is normally for testing.
		else
			# Use me@PRIMARY_HOSTNAME
			EMAIL_ADDR=me@$PRIMARY_HOSTNAME
			EMAIL_PW=12345678
			echo
			echo "Creating a new administrative mail account for $EMAIL_ADDR with password $EMAIL_PW."
			echo
		fi
	else
		echo
		echo "Okay. I'm about to set up $EMAIL_ADDR for you. This account will also"
		echo "have access to the box's control panel."
	fi

	# Create the user's mail account. This will ask for a password if none was given above.
	tools/mail.py user add $EMAIL_ADDR $EMAIL_PW

	# Make it an admin.
	hide_output tools/mail.py user make-admin $EMAIL_ADDR

	# Create an alias to which we'll direct all automatically-created administrative aliases.
	tools/mail.py alias add administrator@$PRIMARY_HOSTNAME $EMAIL_ADDR > /dev/null
fi
