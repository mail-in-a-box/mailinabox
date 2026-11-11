#!/bin/bash
# test file for ALL hashes for all downloaded files,
# used throughout the setup
##########################

source ../setup/functions.sh # load our functions

function wget_verify_all {
    URL=$1
    HASH_SHA1=$2
    HASH_SHA256=$3
    DEST=$4
    # Future release of function will check against provided digest sidecars
    # These will be extremely basic (only available if .sha1 or .sha256)
    SIDECAR_SHA1_DIGEST_AVAILABLE=$5
    SIDECAR_SHA256_DIGEST_AVAILABLE=$6
    CHECKSUM_SHA1="$HASH_SHA1 $DEST"
    CHECKSUM_SHA256="$HASH_SHA256 $DEST"

    # Clear any previously downloaded files
    rm -f "$DEST"

    # Download, then verify both SHA1 and SHA256 hash against expected hash
    hide_output wget -O "$DEST" "$URL"

    echo "Computed hashes..."
    echo "SHA1:"
    sha1sum "$DEST"
    echo "SHA256:"
    sha256sum "$DEST"
    echo
    echo "Verifying hashes..."
    echo "SHA1:"
    if ! echo "$CHECKSUM_SHA1" | sha1sum --check --strict > /dev/null; then
        echo "------------------------------------------------------------"
        echo "FAILED! Expected:"
        echo "$CHECKSUM_SHA1"
    else
        echo "OK!"
    fi
    echo "SHA256:"
    if ! echo "$CHECKSUM_SHA256" | sha256sum --check --strict > /dev/null; then
        echo "------------------------------------------------------------"
        echo "FAILED! Expected:"
        echo "$CHECKSUM_SHA256"
    else
        echo "OK!"
    fi
    echo
}

# How to search these arrays using a version number
function get_nextcloud_version_hashes {
    VERSION=$1

    for index in "${!array_name[@]}"; do
        if [[ "${array_name[$index]}" == "$VERSION" ]]; then
            echo "Found '$VERSION'"
            echo "$index"
        fi
    done

    # Now that we have the index number, we would just search each array
    # using the index, and pass the hashes back by setting a global variable
    #


    ## NEXTCLOUD_HASHES=$($hash_array)
}

## Roundcube
#
declare -a roundcube_version=("1.6.20" "1.7.5")

declare -a roundcube_hash_sha1=("15c70410af3071219aae209ba89e2ff1dacb1ab5" # 1.6.20
    "396b2fa0153bf6b4a8ab99f136b27e16d9f74e57" # 1.7.5
)

declare -a roundcube_hash_sha256=("46919c70c85609b57038903c4ecc4e1d7fa4e14c535fe5b14192d778dcd4a1ee" # 1.6.20
    "93a66c94e3efff7db93187c1c9d7f35546647a3e1e7b9327cc87911564edf9d1" # 1.7.5
)

## CardDAV plugin for Roundcube
#
declare -a carddav_version=("4.4.3")

declare -a carddav_hash_sha1=("74f8ba7aee33e78beb9de07f7f44b81f6071b644") # 4.4.3

declare -a carddav_hash_sha256=("fd36e97f6dd88fa13cec16a6423ea02596a9ac4d11002f19b3eced52feaffdf2") # 4.4.3

## jQuery
#
declare -a jquery_version=("2.2.4")

declare -a jquery_hash_sha1=("69bb69e25ca7d5ef0935317584e6153f3fd9a88c") # 2.2.4

declare -a jquery_hash_sha256=("05b85d96f41fff14d8f608dad03ab71e2c1017c2da0914d7c59291bad7a54f8e") # 2.2.4

## Bootstrap
#
declare -a bootstrap_version=("3.4.1")

declare -a bootstrap_hash_sha1=("0bb64c67c2552014d48ab4db81c2e8c01781f580") # 3.4.1

declare -a bootstrap_hash_sha256=("d49793cf773cbd393ac2cf340c3b4ddab5365fa7c292098ac07e12eab3efd92e") # 3.4.1

## ZPush
#
declare -a zpush_version=("2.7.7")

declare -a zpush_hash_sha1=("b8ba5fdf5594a642c98f92c30683d19b5c6aae77") # 2.7.7

declare -a zpush_hash_sha256=("7a8e0094adf216521ee491078f78e709cd68257d05a868b3992d5665c01d8790") # 2.7.7

## Nextcloud Server
#
# If we want to refactor the upgrade process
# We could just state the desired version number
# and function will determine the number of walks we need to do
# and provide the hashes for each step
# (more upfront work, but better reusability in the long run)
#
# Currently 15 versions (updated as of 10/26/2026) (only version 32 and above will ever change past this date)
declare -a nextcloud_version=("21.0.7" "22.2.6" "23.0.12" "24.0.12" "25.0.7" "26.0.13" "27.1.11" "28.0.14" "29.0.16" "30.0.17" "31.0.14" "32.0.15" "33.0.10" "34.0.5" "35.0.2")
# sha1 values
declare -a nextcloud_hash_sha1=("f5c7079c5b56ce1e301c6a27c0d975d608bb01c9" # 21.0.7
    "9d39741f051a8da42ff7df46ceef2653a1dc70d9" # 22.2.6
    "d138641b8e7aabebe69bb3ec7c79a714d122f729" # 23.0.12
    "7aa5d61632c1ccf4ca3ff00fb6b295d318c05599" # 24.0.12
    "a5a565c916355005c7b408dd41a1e53505e1a080" # 25.0.7
    "d5c10b650e5396d5045131c6d22c02a90572527c" # 26.0.13
    "9f30c01a021c2e5a9e7baff119955afb3c552ebc" # 27.1.11
    "8a9edcfd26d318eb7d1cfa44d69796f2d1098a80" # 28.0.14
    "ceb3014aaddc70d3074d2c69bc6afc76eb1aeff0" # 29.0.16
    "0494197f1984ce8a2f83084c0759a24d48474017" # 30.0.17
    "a891fede2cd4cb3347a406da3fb4f99cd62c89ce" # 31.0.14
    "f13d45819bf2ec3fe83c9c3078324144eff45568" # 32.0.15
    "debd92e9249192368108975433035e7b647563d9" # 33.0.10
    "dd2998ea28f8951cecab5e0e40eb44652686fa04" # 34.0.5
    "73b0fedd3c6c48c5ab26d8105cd8a928f9f8ca5e" # 35.0.2
)
# sha256 values
declare -a nextcloud_hash_sha256=("2be2c2eebe42b41fdbb53e82b1dffc82d3324baeff1ce5392de0fd804052404f" # 21.0.7
      "164c53eaa5ed6d45329935bd33266c16e8a0355541c3c92a39f01af3d359abae" # 22.2.6
      "fee74cff6fbe70c32ded247705c719aadc83d6d2d158e4fd9ce1b3a8945f7830" # 23.0.12
      "4d15c3e9c3c71b54c177d483b939101ac44c1a2cc002fe8dbf1cd700807f028b" # 24.0.12
      "f9552ea261910d993d3712ff9f85e1f48f6e276c7c7c12e78a25519c8ade344a" # 25.0.7
      "5fa3414784fc856cb4903cc2badd19d7baedd7e5ae1e3a17111d4e26f9ae2a20" # 26.0.13
      "ffbfd9857bcaaacaea97d709063b7d81132feb41051063ab6c171c95c6daf142" # 27.1.11
      "593f174f5098c793fb0314fd5847d891ed4e4db908ceba0d4e571544ac855c2d" # 28.0.14
      "6221c764b63369be6122bc414ee26a25bd9ce466f7d9ab29cd5ddb0c124c8eeb" # 29.0.16
      "da51e17762785a36c1cf3fe2dc96cb356870695e384485e5980395493c15caf9" # 30.0.17
      "6f34d623f7c24c5ecb3c165083ddb5d6a10186dbc2fa73a23efda26ec92091a7" # 31.0.14
      "33e7adbe81c1ad0be61123a0fadc63ae2e392759f0c2557e008863eb69c6453d" # 32.0.15
      "ff602a1f1ba202f2137f10eecd201d3e80c5d94fd17ab984c688fb1bcb290645" # 33.0.10
      "d077fdca3dc78ef60b5bbc51182f2a1737aa01e2044d6c23f4e7b72146f5239a" # 34.0.5
      "2f1dcec6a7cdab70346e80a823ccaaa2001a6085013d9f2ae0a2606fa38c2835" # 35.0.2
)

## Nextcloud Contacts
# Compatibility sheet:
# https://apps.nextcloud.com/apps/contacts
#
# Currently 15 versions (updated as of 10/26/2026) (only version 32 and above will ever change past this date)
declare -a nextcloud_contacts_version=("4.2.5" "4.2.5" "4.2.5" "4.2.5" "5.5.4" "5.5.4" "5.5.4" "5.5.4" "6.0.7" "7.3.19" "7.3.19" "8.3.21" "8.9.2" "8.9.2" "8.9.2")
# sha1 values
declare -a nextcloud_contacts_hash_sha1=("f318636decb3b7276c1e63a06de61dcb10f04bbf" # 21.0.7 / 4.2.5
    "f318636decb3b7276c1e63a06de61dcb10f04bbf" # 22.2.6 / 4.2.5
    "f318636decb3b7276c1e63a06de61dcb10f04bbf" # 23.0.12 / 4.2.5
    "f318636decb3b7276c1e63a06de61dcb10f04bbf" # 24.0.12 / 4.2.5
    "c4e3f2183a0088b829f8aa1b3af1f87c9a4c46a2" # 25.0.7 / 5.5.4
    "c4e3f2183a0088b829f8aa1b3af1f87c9a4c46a2" # 26.0.13 / 5.5.4
    "c4e3f2183a0088b829f8aa1b3af1f87c9a4c46a2" # 27.1.11 / 5.5.4
    "c4e3f2183a0088b829f8aa1b3af1f87c9a4c46a2" # 28.0.14 / 5.5.4
    "babb779107b029c30ad20b81da33b4f95e1136ff" # 29.0.16 / 6.0.7
    "bd680b3b96f09d013ff3a12eccb352b83f3bcd51" # 30.0.17 / 7.3.19
    "bd680b3b96f09d013ff3a12eccb352b83f3bcd51" # 31.0.14 / 7.3.19
    "ee13e775ae9567dd8454d0d4a3e4393878658f6a" # 32.0.15 / 8.3.21
    "9539f80acbdf9a9dd3f3a7006939b785c8bafe18" # 33.0.10 / 8.9.2
    "9539f80acbdf9a9dd3f3a7006939b785c8bafe18" # 34.0.5 / 8.9.2
    "9539f80acbdf9a9dd3f3a7006939b785c8bafe18" # 35.0.2 / 8.9.2
)
# sha256 values
declare -a nextcloud_contacts_hash_sha256=("c72f1d934d7546a59ead3dd57804aadf3c3092cf91e9b53d3610ff16aa50df73" # 21.0.7 / 4.2.5
      "c72f1d934d7546a59ead3dd57804aadf3c3092cf91e9b53d3610ff16aa50df73" # 22.2.6 / 4.2.5
      "c72f1d934d7546a59ead3dd57804aadf3c3092cf91e9b53d3610ff16aa50df73" # 23.0.12 / 4.2.5
      "c72f1d934d7546a59ead3dd57804aadf3c3092cf91e9b53d3610ff16aa50df73" # 24.0.12 / 4.2.5
      "178aa6ec0b06d6bd72ff8eb87ac32ff267e97ccd93246b1eae1b5bb5263a61b0" # 25.0.7 / 5.5.4
      "178aa6ec0b06d6bd72ff8eb87ac32ff267e97ccd93246b1eae1b5bb5263a61b0" # 26.0.13 / 5.5.4
      "178aa6ec0b06d6bd72ff8eb87ac32ff267e97ccd93246b1eae1b5bb5263a61b0" # 27.1.11 / 5.5.4
      "178aa6ec0b06d6bd72ff8eb87ac32ff267e97ccd93246b1eae1b5bb5263a61b0" # 28.0.14 / 5.5.4
      "29b4942b9b224dcb7e7528fafb6a6094e45593e893dff61e519c34b19bed29a6" # 29.0.16 / 6.0.7
      "568472420cf212ceeb1dccc044c0bdaa83504ef15251a2c6e39b22b6064a3ab8" # 30.0.17 / 7.3.19
      "568472420cf212ceeb1dccc044c0bdaa83504ef15251a2c6e39b22b6064a3ab8" # 31.0.14 / 7.3.19
      "45d12ff526515ce5efc52d8e0d42bd3446a66b9a423ee4eb92ebd44a6b5974c3" # 32.0.15 / 8.3.21
      "92f7c79c411273045ed6346f6988c05af673c3170a3adaba91a15066b8dce7c5" # 33.0.10 / 8.9.2
      "92f7c79c411273045ed6346f6988c05af673c3170a3adaba91a15066b8dce7c5" # 34.0.5 / 8.9.2
      "92f7c79c411273045ed6346f6988c05af673c3170a3adaba91a15066b8dce7c5" # 35.0.2 / 8.9.2
)

## Nextcloud Calendar
# Compatibility sheet:
# https://apps.nextcloud.com/apps/calendar
#
# Currently 15 versions (updated as of 10/26/2026) (only version 32 and above will ever change past this date)
declare -a nextcloud_calendar_version=("3.3.3" "3.5.9" "3.5.9" "3.5.9" "4.6.8" "4.7.20" "4.7.20" "4.7.20" "4.7.20" "5.5.24" "5.5.24" "6.6.4" "6.6.4" "6.6.4" "6.6.4")
# sha1 values
declare -a nextcloud_calendar_hash_sha1=("2bbb534d95fe1e0a7368ca3a7c10d6374705a6c1" # 21.0.7 / 3.3.3
    "cb3b4df6c9aa99bfc055ab56ba4b7fdcd8e4629d" # 22.2.6 / 3.5.9
    "cb3b4df6c9aa99bfc055ab56ba4b7fdcd8e4629d" # 23.0.12 / 3.5.9
    "cb3b4df6c9aa99bfc055ab56ba4b7fdcd8e4629d" # 24.0.12 / 3.5.9
    "b01187e58a18a35774ed6fa97c1d336454208ddd" # 25.0.7 / 4.6.8
    "12d876904e227156e39ca4335b18481b42a6d00f" # 26.0.13 / 4.7.20
    "12d876904e227156e39ca4335b18481b42a6d00f" # 27.1.11 / 4.7.20
    "12d876904e227156e39ca4335b18481b42a6d00f" # 28.0.14 / 4.7.20
    "12d876904e227156e39ca4335b18481b42a6d00f" # 29.0.16 / 4.7.20
    "a7722f0511a1165e6a51c1944288ed4518723791" # 30.0.17 / 5.5.24
    "a7722f0511a1165e6a51c1944288ed4518723791" # 31.0.14 / 5.5.24
    "587cba617e9557d6963ad651272e673dc0dfd4ba" # 32.0.15 / 6.6.4
    "587cba617e9557d6963ad651272e673dc0dfd4ba" # 33.0.10 / 6.6.4
    "587cba617e9557d6963ad651272e673dc0dfd4ba" # 34.0.5 / 6.6.4
    "587cba617e9557d6963ad651272e673dc0dfd4ba" # 35.0.2 / 6.6.4
)
# sha256 values
declare -a nextcloud_calendar_hash_sha256=("f7d7ee968d03ee4950c99f02a4c9afacb58fac2b0e97ef3b2b56bbbe6a5aceca" # 21.0.7 / 3.3.3
      "024b68d8eb7e795188928c5de5b7ba490cec75810aee3f2558ada6b3c4c8cb36" # 22.2.6 / 3.5.9
      "024b68d8eb7e795188928c5de5b7ba490cec75810aee3f2558ada6b3c4c8cb36" # 23.0.12 / 3.5.9
      "024b68d8eb7e795188928c5de5b7ba490cec75810aee3f2558ada6b3c4c8cb36" # 24.0.12 / 3.5.9
      "3c0f3a57241eea547ce8052aa143f5c9ddbb8211a2db655a64235db57548691a" # 25.0.7 / 4.6.8
      "f62b43853dfc1fc971b4ffe5992cedc499e8ed7dc118265cfdfe8c1531d4a912" # 26.0.13 / 4.7.20
      "f62b43853dfc1fc971b4ffe5992cedc499e8ed7dc118265cfdfe8c1531d4a912" # 27.1.11 / 4.7.20
      "f62b43853dfc1fc971b4ffe5992cedc499e8ed7dc118265cfdfe8c1531d4a912" # 28.0.14 / 4.7.20
      "f62b43853dfc1fc971b4ffe5992cedc499e8ed7dc118265cfdfe8c1531d4a912" # 29.0.16 / 4.7.20
      "9a4e1b869aa478317363cb0876a5d128aa584e427216d2cbfb808215f5c296a8" # 30.0.17 / 5.5.24
      "9a4e1b869aa478317363cb0876a5d128aa584e427216d2cbfb808215f5c296a8" # 31.0.14 / 5.5.24
      "0557b6b5852a467cf3f746e59d56478d227f78bf7a66357b30dfc10cae4c7e3c" # 32.0.15 / 6.6.4
      "0557b6b5852a467cf3f746e59d56478d227f78bf7a66357b30dfc10cae4c7e3c" # 33.0.10 / 6.6.4
      "0557b6b5852a467cf3f746e59d56478d227f78bf7a66357b30dfc10cae4c7e3c" # 34.0.5 / 6.6.4
      "0557b6b5852a467cf3f746e59d56478d227f78bf7a66357b30dfc10cae4c7e3c" # 35.0.2 / 6.6.4
)

## Nextcloud user_external
# Compatibility sheet:
# https://apps.nextcloud.com/apps/user_external
#
# Currently 15 versions (updated as of 10/26/2026) (only version 32 and above will ever change past this date)
declare -a nextcloud_user_external_version=("2.1.0" "3.1.0" "3.1.0" "3.1.0" "3.4.0" "3.4.0" "3.4.0" "3.4.0" "3.4.0" "3.4.0" "4.0.0" "4.0.0" "4.0.0" "4.0.0" "4.0.0")
# sha1 values
declare -a nextcloud_user_external_hash_sha1=("6e5afe7f36f398f864bfdce9cad72200e70322aa" # 21.0.7 / 2.1.0
    "22cabc88b6fc9c26dad3b46be1a652979c9fcf15" # 22.2.6 / 3.1.0
    "22cabc88b6fc9c26dad3b46be1a652979c9fcf15" # 23.0.12 / 3.1.0
    "22cabc88b6fc9c26dad3b46be1a652979c9fcf15" # 24.0.12 / 3.1.0
    "7f9d8f4dd6adb85a0e3d7622d85eeb7bfe53f3b4" # 25.0.7 / 3.4.0
    "7f9d8f4dd6adb85a0e3d7622d85eeb7bfe53f3b4" # 26.0.13 / 3.4.0
    "7f9d8f4dd6adb85a0e3d7622d85eeb7bfe53f3b4" # 27.1.11 / 3.4.0
    "7f9d8f4dd6adb85a0e3d7622d85eeb7bfe53f3b4" # 28.0.14 / 3.4.0
    "7f9d8f4dd6adb85a0e3d7622d85eeb7bfe53f3b4" # 29.0.16 / 3.4.0
    "7f9d8f4dd6adb85a0e3d7622d85eeb7bfe53f3b4" # 30.0.17 / 3.4.0
    "214497dd8691f279ba3740797c565310f0793054" # 31.0.14 / 4.0.0
    "214497dd8691f279ba3740797c565310f0793054" # 32.0.15 / 4.0.0
    "214497dd8691f279ba3740797c565310f0793054" # 33.0.10 / 4.0.0
    "214497dd8691f279ba3740797c565310f0793054" # 34.0.5 / 4.0.0
    "214497dd8691f279ba3740797c565310f0793054" # 35.0.2 / 4.0.0
)
# sha256 values
declare -a nextcloud_user_external_hash_sha256=("79d400c05737ea3512faf0ab77411dd5da9c830341e59b1a98b86775c92acf19" # 21.0.7 / 2.1.0
      "8bb7db302b25045f70317823b64cc66b684d5bdf7d68817840169bdc726ce6dc" # 22.2.6 / 3.1.0
      "8bb7db302b25045f70317823b64cc66b684d5bdf7d68817840169bdc726ce6dc" # 23.0.12 / 3.1.0
      "8bb7db302b25045f70317823b64cc66b684d5bdf7d68817840169bdc726ce6dc" # 24.0.12 / 3.1.0
      "5a7fbed5da3cbe335f753027b662179c92c17fb37babc875e9e285d8a13d47f3" # 25.0.7 / 3.4.0
      "5a7fbed5da3cbe335f753027b662179c92c17fb37babc875e9e285d8a13d47f3" # 26.0.13 / 3.4.0
      "5a7fbed5da3cbe335f753027b662179c92c17fb37babc875e9e285d8a13d47f3" # 27.1.11 / 3.4.0
      "5a7fbed5da3cbe335f753027b662179c92c17fb37babc875e9e285d8a13d47f3" # 28.0.14 / 3.4.0
      "5a7fbed5da3cbe335f753027b662179c92c17fb37babc875e9e285d8a13d47f3" # 29.0.16 / 3.4.0
      "5a7fbed5da3cbe335f753027b662179c92c17fb37babc875e9e285d8a13d47f3" # 30.0.17 / 3.4.0
      "f1f98c577bd02177fe74e9199f8e50d0c288ffa94bb50a227101a5ba0633c529" # 31.0.14 / 4.0.0
      "f1f98c577bd02177fe74e9199f8e50d0c288ffa94bb50a227101a5ba0633c529" # 32.0.15 / 4.0.0
      "f1f98c577bd02177fe74e9199f8e50d0c288ffa94bb50a227101a5ba0633c529" # 33.0.10 / 4.0.0
      "f1f98c577bd02177fe74e9199f8e50d0c288ffa94bb50a227101a5ba0633c529" # 34.0.5 / 4.0.0
      "f1f98c577bd02177fe74e9199f8e50d0c288ffa94bb50a227101a5ba0633c529" # 35.0.2 / 4.0.0
)

#########
# Testing blocks
#########

# Roundcube Webmail
#for i in "${!roundcube_version[@]}"; do
#    echo "Testing Roundcube Webmail SHAs for version" "${roundcube_version[$i]}"
#    wget_verify_all "https://github.com/roundcube/roundcubemail/releases/download/${roundcube_version[$i]}/roundcubemail-${roundcube_version[$i]}-complete.tar.gz" "${roundcube_hash_sha1[$i]}" "${roundcube_hash_sha256[$i]}" /tmp/roundcube-${roundcube_version[$i]}.tgz "false" "false"
#    rm -f /tmp/roundcube-${roundcube_version[$i]}.tgz
#done

# CardDav Plugin for Roundcube
#for i in "${!carddav_version[@]}"; do
#    echo "Testing CardDav Plugin SHAs for version" "${carddav_version[$i]}"
#    wget_verify_all "https://github.com/mstilkerich/rcmcarddav/releases/download/v${carddav_version[$i]}/carddav-v${carddav_version[$i]}.tar.gz" "${carddav_hash_sha1[$i]}" "${carddav_hash_sha256[$i]}" /tmp/carddav-${carddav_version[$i]}.tar.gz "false" "false"
#    rm -f /tmp/carddav-${carddav_version[$i]}.tar.gz
#done

# jQuery
#for i in "${!jquery_version[@]}"; do
#    echo "Testing jQuery SHAs for version" "${jquery_version[$i]}"
#    wget_verify_all "https://code.jquery.com/jquery-${jquery_version[$i]}.min.js" "${jquery_hash_sha1[$i]}" "${jquery_hash_sha256[$i]}" /tmp/jquery-${jquery_version[$i]}.min.js "false" "false"
#    rm -f /tmp/jquery-${jquery_version[$i]}.min.js
#done

# Bootstrap
#for i in "${!bootstrap_version[@]}"; do
#    echo "Testing Bootstrap SHAs for version" "${bootstrap_version[$i]}"
#    wget_verify_all "https://github.com/twbs/bootstrap/releases/download/v${bootstrap_version[$i]}/bootstrap-${bootstrap_version[$i]}-dist.zip" "${bootstrap_hash_sha1[$i]}" "${bootstrap_hash_sha256[$i]}" /tmp/bootstrap-${bootstrap_version[$i]}.zip "false" "false"
#    rm -f /tmp/bootstrap-${bootstrap_version[$i]}.zip
#done

# ZPush
#for i in "${!zpush_version[@]}"; do
#    echo "Testing ZPush SHAs for version" "${zpush_version[$i]}"
#    wget_verify_all "https://github.com/Z-Hub/Z-Push/archive/refs/tags/${zpush_version[$i]}.zip" "${zpush_hash_sha1[$i]}" "${zpush_hash_sha256[$i]}" /tmp/z-push-${zpush_version[$i]}.zip "false" "false"
#    rm -f /tmp/z-push-${zpush_version[$i]}.zip
#done

# Nextcloud Server
#for i in "${!nextcloud_version[@]}"; do
#    echo "Testing Nextcloud Server SHAs for version" "${nextcloud_version[$i]}"
#    wget_verify_all "https://download.nextcloud.com/server/releases/nextcloud-${nextcloud_version[$i]}.zip" "${nextcloud_hash_sha1[$i]}" "${nextcloud_hash_sha256[$i]}" /tmp/nextcloud-${nextcloud_version[$i]}.zip "false" "false"
#    rm -f /tmp/nextcloud-${nextcloud_version[$i]}.zip
#done

# Nextcloud Contacts App
#for i in "${!nextcloud_contacts_version[@]}"; do
#    echo "Testing Nextcloud Contacts SHAs for version" "${nextcloud_contacts_version[$i]}"
#    wget_verify_all "https://github.com/nextcloud-releases/contacts/releases/download/v${nextcloud_contacts_version[$i]}/contacts-v${nextcloud_contacts_version[$i]}.tar.gz" "${nextcloud_contacts_hash_sha1[$i]}" "${nextcloud_contacts_hash_sha256[$i]}" /tmp/contacts-${nextcloud_contacts_version[$i]}.tgz "false" "false"
#    rm -f /tmp/contacts-${nextcloud_contacts_version[$i]}.tgz
#done

# Nextcloud Calendar App
#for i in "${!nextcloud_calendar_version[@]}"; do
#    echo "Testing Nextcloud Calendar SHAs for version" "${nextcloud_calendar_version[$i]}"
#    wget_verify_all "https://github.com/nextcloud-releases/calendar/releases/download/v${nextcloud_calendar_version[$i]}/calendar-v${nextcloud_calendar_version[$i]}.tar.gz" "${nextcloud_calendar_hash_sha1[$i]}" "${nextcloud_calendar_hash_sha256[$i]}" /tmp/calendar-${nextcloud_calendar_version[$i]}.tgz "false" "false"
#    rm -f /tmp/calendar-${nextcloud_calendar_version[$i]}.tgz
#done

# Nextcloud user_external App
#for i in "${!nextcloud_user_external_version[@]}"; do
#    echo "Testing Nextcloud user_external SHAs for version" "${nextcloud_user_external_version[$i]}"
    # 2.1.0 uses a different repo, but still hosted by Nextcloud
#    if [[ ${nextcloud_user_external_version[$i]} == "2.1.0" ]]; then
#        wget_verify_all "https://github.com/nextcloud/user_external/releases/download/v${nextcloud_user_external_version[$i]}/user_external-2.1.0.tar.gz" "${nextcloud_user_external_hash_sha1[$i]}" "${nextcloud_user_external_hash_sha256[$i]}" /tmp/user_external-${nextcloud_user_external_version[$i]}.tgz "false" "false"
#    else
#        wget_verify_all "https://github.com/nextcloud-releases/user_external/releases/download/v${nextcloud_user_external_version[$i]}/user_external-v${nextcloud_user_external_version[$i]}.tar.gz" "${nextcloud_user_external_hash_sha1[$i]}" "${nextcloud_user_external_hash_sha256[$i]}" /tmp/user_external-${nextcloud_user_external_version[$i]}.tgz "false" "false"
#    fi
#    rm -f /tmp/user_external-${nextcloud_user_external_version[$i]}.tgz
#done
