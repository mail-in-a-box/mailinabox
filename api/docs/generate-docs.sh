#!/usr/bin/env sh
#####
##### This file is part of Mail-in-a-Box-LDAP which is released under the
##### terms of the GNU Affero General Public License as published by the
##### Free Software Foundation, either version 3 of the License, or (at
##### your option) any later version. See file LICENSE or go to
##### https://github.com/downtownallday/mailinabox-ldap for full license
##### details.
#####


# Requirements:
# - Node.js
# - redoc-cli (`npm install redoc-cli -g`)

redoc-cli bundle ../mailinabox.yml \
  -t template.hbs \
  -o api-docs.html \
  --templateOptions.metaDescription="Mail-in-a-Box HTTP API" \
  --title="Mail-in-a-Box HTTP API" \
  --options.expandSingleSchemaField \
  --options.hideSingleRequestSampleTab \
  --options.jsonSampleExpandLevel=10 \
  --options.hideDownloadButton \
  --options.theme.logo.maxHeight=180px \
  --options.theme.logo.maxWidth=180px \
  --options.theme.colors.primary.main="#C52" \
  --options.theme.typography.fontSize=16px \
  --options.theme.typography.fontFamily="Raleway, sans-serif" \
  --options.theme.typography.headings.fontFamily="Ubuntu, Arial, sans-serif" \
  --options.theme.typography.code.fontSize=15px \
  --options.theme.typography.code.fontFamily='"Source Code Pro", monospace'