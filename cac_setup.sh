#!/usr/bin/env bash

# cac_setup.sh
# Description: Setup a Linux environment for Common Access Card use.

main ()
{
    # For colorization
    ERR_COLOR='\033[0;31m'  # Red for error messages
    INFO_COLOR='\033[0;33m' # Yellow for notes
    NO_COLOR='\033[0m'      # Revert terminal back to no color

    EXIT_SUCCESS=0          # Success exit code
    E_INSTALL=85            # Installation failed
    E_NOTROOT=86            # Non-root exit error
    E_BROWSER=87            # Compatible browser not found
    ROOT_UID=0              # Only users with $UID 0 have root privileges
    DWNLD_DIR="/tmp"        # Reliable location to place artifacts
    CHROME_EXISTS=0         # Google Chrome is installed
    ff_exists=0             # Firefox is installed
    snap_ff=0               # Flag to prompt for how to handle snap Firefox

    ORIG_HOME="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
    CERT_EXTENSION="cer"
    PKCS_FILENAME="pkcs11.txt"
    DB_FILENAME="cert9.db"
    CERT_FILENAME="AllCerts"
    BUNDLE_FILENAME="AllCerts.zip"
    CERT_URL="http://militarycac.com/maccerts/$BUNDLE_FILENAME"
    PKG_FILENAME="cackey_0.7.5-1_amd64.deb"
    CACKEY_URL="http://cackey.rkeene.org/download/0.7.5/$PKG_FILENAME"

    # Ensure the script is ran as root
    if [ "${EUID:-$(id -u)}" -ne "$ROOT_UID" ]
    then
        echo -e "${ERR_COLOR}[ERROR]${NO_COLOR} Please run this script as root."
        exit "$E_NOTROOT"
    fi

    # Check to see if firefox exists
    echo -e "${INFO_COLOR}[INFO]${NO_COLOR} Checking for Firefox and Chrome..."
    if which firefox >/dev/null
    then
        ff_exists=1
        echo -e "${INFO_COLOR}[INFO]${NO_COLOR} Found Firefox."
        echo -e "${INFO_COLOR}[INFO]${NO_COLOR} Installation method:"
        if which firefox | grep snap >/dev/null
        then
            snap_ff=1
            echo -e "${ERR_COLOR}\t(oh) SNAP!${NO_COLOR}"
        else

        echo -e "${INFO_COLOR}\tapt (or just not snap):${NO_COLOR}"
        fi
    else

        echo -e "${INFO_COLOR}[INFO]${NO_COLOR} Firefox not found."
    fi

    # Check to see if Chrome exists
    if which google-chrome >/dev/null
    then
        CHROME_EXISTS=1
        echo -e "${INFO_COLOR}[INFO]${NO_COLOR} Found Google Chrome."
    else
        echo -e "${INFO_COLOR}[INFO]${NO_COLOR} Chrome not found."
    fi

    # Browser check results
    if [ "$ff_exists" -eq 0 ] && [ "$CHROME_EXISTS" -eq 0 ]
    then
        echo -e "${ERR_COLOR}No version of Mozilla Firefox OR Google Chrome have been detected.\nPlease install either or both to proceed.${NO_COLOR}"

        exit "$E_BROWSER"

    elif [ "$ff_exists" -eq 1 ]
    then
        if [ "$snap_ff" -eq 1 ]
        then
            echo -e "
            ********************${INFO_COLOR}[IMPORTANT]${NO_COLOR}********************
            * The version of Firefox you have installed       *
            * currently was installed via snap.               *
            * This version of Firefox is not currently        *
            * compatible with the method used to enable CAC   *
            * support in browsers.                            *
            *                                                 *
            * As a work-around, this script can automatically *
            * remove the snap version and reinstall via apt.  *
            *                                                 *
            * If you are not signed in to Firefox, you will   *
            * likely lose bookmarks or other personalizations *
            * set in the current variant of Firefox.          *
            ********************${INFO_COLOR}[IMPORTANT]${NO_COLOR}********************\n"

            # Prompt user to elect to replace snap firefox with apt firefox
            choice=''
            while [ "$choice" != "y" ] && [ "$choice" != "n" ]
            do
                echo -e "${ERR_COLOR}\nWould you like to proceed with the switch to the apt version? ${INFO_COLOR}(\"y/n\")${NO_COLOR}"

                read -rp '> ' choice
            done

            if [ "$choice" == "y" ]
            then
            # Replace snap Firefox with version from PPA maintained via Mozilla
                echo -e "${INFO_COLOR}[INFO]${NO_COLOR} Removing Snap version of Firefox"
                snap remove --purge firefox
                echo -e "${INFO_COLOR}[INFO]${NO_COLOR} Adding PPA for Mozilla maintained Firefox"
                add-apt-repository -y ppa:mozillateam/ppa
                echo -e "${INFO_COLOR}[INFO]${NO_COLOR} Setting priority to prefer Mozilla PPA over snap package"
                echo -e "Package: *\nPin: release o=LP-PPA-mozillateam\nPin-Priority: 1001" | tee /etc/apt/preferences.d/mozilla-firefox
                echo -e "${INFO_COLOR}[INFO]${NO_COLOR} Enabling updates for future firefox releases"
                echo -e 'Unattended-Upgrade::Allowed-Origins:: "LP-PPA-mozillateam:${distro_codename}";' | tee /etc/apt/apt.conf.d/51unattended-upgrades-firefox
                echo -e "${INFO_COLOR}[INFO]${NO_COLOR} Installing Firefox via apt"
                apt install firefox -y
                echo -e "${INFO_COLOR}[INFO]${NO_COLOR} Completed re-installation of Firefox"

                # Forget the old location of firefox
                hash -d firefox

                echo -e "${INFO_COLOR}[INFO]${NO_COLOR} Starting Firefox silently to complete post-install actions..."
                firefox --headless --first-startup >/dev/null 2>1 &
                sleep 2

                pkill -9 firefox
                echo -e "${INFO_COLOR}[INFO]${NO_COLOR} Finished, closing Firefox."

                snap_ff=0
            else
                if [ $CHROME_EXISTS -eq 0 ]
                then
                    echo -e "You have elected to keep the snap version of Firefox. You also do not currently have Google Chrome installed. Therefore, you have no compatible browsers. \n\n Exiting!\n"

                    exit $E_BROWSER
                fi
            fi
        fi
    fi



    # Install middleware and necessary utilities
    echo -e "${INFO_COLOR}[INFO]${NO_COLOR} Installing middleware..."
    apt update
    DEBIAN_FRONTEND=noninteractive apt install -y libpcsclite1 pcscd libccid libpcsc-perl pcsc-tools libnss3-tools unzip wget
    echo "Done"

    # Pull all necessary files
    echo -e "${INFO_COLOR}[INFO]${NO_COLOR} Downloading DoD certificates and Cackey package..."
    wget -qP "$DWNLD_DIR" "$CERT_URL"
    wget -qP "$DWNLD_DIR" "$CACKEY_URL"
    echo "Done."

    # Install libcackey.
    echo -e "${INFO_COLOR}[INFO]${NO_COLOR} Installing libcackey..."
    if dpkg -i "$DWNLD_DIR/$PKG_FILENAME"
    then
        echo "Done."
    else
        echo -e "${ERR_COLOR}[ERROR]${NO_COLOR} Installation failed. Exiting..."
        exit "$E_INSTALL"
    fi

    # Prevent cackey from upgrading.
    # If cackey upgrades beyond 7.5, it moves libcackey.so to a different location,
    # breaking Firefox. Returning libcackey.so to the original location does not
    # seem to fix this issue.
    if apt-mark hold cackey
    then
        echo -e "${INFO_COLOR}[INFO]${NO_COLOR} Hold placed on cackey package"
    else
        echo -e "${ERR_COLOR}[ERROR]${NO_COLOR} Failed to place hold on cackey package"
    fi

    # Unzip cert bundle
    mkdir -p "$DWNLD_DIR/$CERT_FILENAME"
    unzip "$DWNLD_DIR/$BUNDLE_FILENAME" -d "$DWNLD_DIR/$CERT_FILENAME"

    # From testing on Ubuntu 22.04, this process doesn't seem to work well with applications
    # installed via snap, so the script will ignore databases within snap.
    mapfile -t databases < <(find "$ORIG_HOME" -name "$DB_FILENAME" 2>/dev/null | grep "firefox\|pki" | grep -v "snap")
    for db in "${databases[@]}"
    do
        if [ -n "$db" ]
        then
            db_root="$(dirname "$db")"
            if [ -n "$db_root" ]
            then
                case "$db_root" in
                    *"pki"*)
                        echo -e "${INFO_COLOR}[INFO]${NO_COLOR} Importing certificates for Chrome..."
                        echo
                        ;;
                    *"firefox"*)
                        echo -e "${INFO_COLOR}[INFO]${NO_COLOR} Importing certificates for Firefox..."
                        echo
                        ;;
                esac

                echo -e "${INFO_COLOR}[INFO]${NO_COLOR} Loading certificates into $db_root "
                echo

                for cert in "$DWNLD_DIR/$CERT_FILENAME/"*."$CERT_EXTENSION"
                do
                    echo "Importing $cert"
                    certutil -d sql:"$db_root" -A -t TC -n "$cert" -i "$cert"
                done

                if ! grep -Pzo 'library=/usr/lib64/libcackey.so\nname=CAC Module\n' "$db_root/$PKCS_FILENAME" >/dev/null
                then
                    printf "library=/usr/lib64/libcackey.so\nname=CAC Module\n" >> "$db_root/$PKCS_FILENAME"
                fi
            fi

            echo "Done."
            echo
        else
            echo -e "${INFO_COLOR}[INFO]${NO_COLOR} No databases found."
        fi
    done

    # Remove artifacts
    echo -e "${INFO_COLOR}[INFO]${NO_COLOR} Removing artifacts..."
    rm -rf "${DWNLD_DIR:?}"/{"$BUNDLE_FILENAME","$CERT_FILENAME","$PKG_FILENAME"}
    if [ "$?" -ne "$EXIT_SUCCESS" ]
    then
        echo -e "${ERR_COLOR}[ERROR]${NO_COLOR} Failed to remove artifacts"
    else
        echo "Done."
    fi

    exit "$EXIT_SUCCESS"
}

main
