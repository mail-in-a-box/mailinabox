<?php
	$resource = $_GET['resource'];

	header("Content-type: application/json");
	echo json_encode(array(
		subject => $resource,
	), JSON_PRETTY_PRINT);
?>

