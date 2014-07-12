<?php
	// Parse our configuration file to get the PRIMARY_HOSTNAME.
	$PRIMARY_HOSTNAME = NULL;
	foreach (file("/etc/mailinabox.conf") as $line) {
		$line = explode("=", rtrim($line), 2);
		if ($line[0] == "PRIMARY_HOSTNAME") {
			$PRIMARY_HOSTNAME = $line[1];
		}
	}
	if ($PRIMARY_HOSTNAME == NULL) exit("no PRIMARY_HOSTNAME");

	// We might get two kinds of requests.
	$post_body = file_get_contents('php://input');
	preg_match('/<AcceptableResponseSchema>(.*?)<\/AcceptableResponseSchema>/', $post_body, $match);
	$AcceptableResponseSchema = $match[1];

	if ($AcceptableResponseSchema == "http://schemas.microsoft.com/exchange/autodiscover/mobilesync/responseschema/2006") {
		// There is no way to convey the user's login name with this?
		?>
<?xml version="1.0" encoding="utf-8"?>
<Autodiscover
xmlns:autodiscover="http://schemas.microsoft.com/exchange/autodiscover/mobilesync/responseschema/2006">
    <autodiscover:Response>
        <autodiscover:Action>
            <autodiscover:Settings>
                <autodiscover:Server>
                    <autodiscover:Type>MobileSync</autodiscover:Type>
                    <autodiscover:Url>https://<?php echo $PRIMARY_HOSTNAME ?></autodiscover:Url>
                    <autodiscover:Name>https://<?php echo $PRIMARY_HOSTNAME ?></autodiscover:Name>
                </autodiscover:Server>
            </autodiscover:Settings>
        </autodiscover:Action>
    </autodiscover:Response>
</Autodiscover>
<?php
	} else {

	// I don't know when this is actually used. I implemented this before seeing that
	// it is not what my phone wanted.

	// Parse the email address out of the POST request, which
	// we pass back as the login name.
	preg_match('/<EMailAddress>(.*?)<\/EMailAddress>/', $post_body, $match);
	$LOGIN = $match[1];

	header("Content-type: text/xml");
?>
<?xml version="1.0" encoding="utf-8" ?>
<Autodiscover xmlns="http://schemas.microsoft.com/exchange/autodiscover/responseschema/2006">
	<Response xmlns="http://schemas.microsoft.com/exchange/autodiscover/outlook/responseschema/2006a">
		<ServiceHome>https://<?php echo $PRIMARY_HOSTNAME ?></ServiceHome>
		<Account>
			<AccountType>email</AccountType>
			<Action>settings</Action>

			<Protocol>
				<Type>IMAP</Type>
				<Server><?php echo $PRIMARY_HOSTNAME ?></Server>
				<Port>993</Port>
				<SSL>on</SSL>
				<LoginName><?php echo $LOGIN ?></LoginName>
			</Protocol>

			<Protocol>
				<Type>SMTP</Type>
				<Server><?php echo $PRIMARY_HOSTNAME ?></Server>
				<Port>587</Port>
				<SSL>on</SSL>
				<LoginName><?php echo $LOGIN ?></LoginName>
			</Protocol>

			<Protocol>
				<Type>DAV</Type>
				<Server>https://<?php echo $PRIMARY_HOSTNAME ?></Server>
				<SSL>on</SSL>
				<DomainRequired>on</DomainRequired>
				<LoginName><?php echo $LOGIN ?></LoginName>
			</Protocol>

			<Protocol>
				<Type>WEB</Type>
				<Server>https://<?php echo $PRIMARY_HOSTNAME ?>/mail</Server>
				<SSL>on</SSL>
			</Protocol>
		</Account>
	</Response>
</Autodiscover>

	<?php
	}
	?>

