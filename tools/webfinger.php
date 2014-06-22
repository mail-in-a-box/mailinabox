<?php
	$resource = $_GET['resource'];

	// Parse our configuration file to get the STORAGE_ROOT.
	$STORAGE_ROOT = NULL;
	foreach (file("/etc/mailinabox.conf") as $line) {
		$line = explode("=", rtrim($line), 2);
		if ($line[0] == "STORAGE_ROOT") {
			$STORAGE_ROOT = $line[1];
		}
	}
	if ($STORAGE_ROOT == NULL) exit("no STORAGE_ROOT");

	// Turn the resource into a file path. First URL-encode the resource
	// so that it is filepath-safe.
	$fn = urlencode($resource);

	// Replace the first colon (it's URL-encoded) with a slash since we'll
	// break off the files into scheme subdirectories.
	$fn = preg_replace("/%3A/", "/", $fn, 1);

	// Since this is often for email addresses, un-escape @-signs so they
	// are not odd-looking. It's filename-safe anyway.
	$fn = preg_replace("/%40/", "@", $fn);

	// Combine with root path.
	$fn = $STORAGE_ROOT . "/webfinger/" . $fn . ".json";

	// See if the file exists.
	if (!file_exists($fn)) {
		header("HTTP/1.0 404 Not Found");
		exit;
	}

	header("Content-type: application/json");
	echo file_get_contents($fn);

	//json_encode(array(
	//	subject => $resource,
	//), JSON_PRETTY_PRINT);
?>

