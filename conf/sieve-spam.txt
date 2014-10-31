require ["regex", "fileinto", "imap4flags"];

if allof (header :regex "X-Spam-Status" "^Yes") {
  fileinto "Spam";
  stop;
}

