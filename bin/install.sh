#!/bin/bash
usage() {
	pname=$(basename $0)
	echo "Usage:"
	echo "$pname --prefix InstallDirectory --runuser USER_RunON --port ListenPort --pkgurl PACKAGE_URL --downloaduser Download_User --downloadpwd Download_Password --registerurl REGISTER_URL"
	echo ""
	echo "--prefix: Directory to install, default:/opt/tagent"
	echo "--user: User to run on, default:root"
	echo "--port: Agent listen port, default:3939"
	echo "--pkgurl: Agent install package download url, support http|https|ftp"
	echo "--downloaduser: Access download url username, default:none"
	echo "--downloadpwd: Access download url password, defualt:none"
	echo "--serveraddr: Agent register call back http base url"
	echo "--tenant: System tenant"
	echo ""
	echo "Example:$pname --user root --port 3939 --tenant develop --pkgurl http://abc.com/service/tagent.tar --serveraddr 'http://192.168.0.88:8080'"
	exit -1
}

parseOpts() {
	OPT_SPEC=":h-:"
	while getopts "$OPT_SPEC" optchar; do
		case "${optchar}" in
		-)
			case "${OPTARG}" in
			prefix)
				INS_DIR="${!OPTIND}"
				OPTIND=$(($OPTIND + 1))
				;;
			runuser)
				USER_RUNON="${!OPTIND}"
				OPTIND=$(($OPTIND + 1))
				;;
			downloaduser)
				DOWNLOAD_USER="${!OPTIND}"
				OPTIND=$(($OPTIND + 1))
				;;
			downloadpwd)
				DOWNLOAD_PWD="${!OPTIND}"
				OPTIND=$(($OPTIND + 1))
				;;
			listenaddr)
				LISTEN_ADDR="${!OPTIND}"
				OPTIND=$(($OPTIND + 1))
				;;
			port)
				PORT="${!OPTIND}"
				OPTIND=$(($OPTIND + 1))
				;;
			pkgurl)
				PKG_URL="${!OPTIND}"
				OPTIND=$(($OPTIND + 1))
				;;
			serveraddr)
				SRV_ADDR="${!OPTIND}"
				OPTIND=$(($OPTIND + 1))
				;;
			tenant)
				TENANT="${!OPTIND}"
				OPTIND=$(($OPTIND + 1))
				;;
			*)
				if [ "$OPTERR" = 1 ] && [ "${OPT_SPEC:0:1}" != ":" ]; then
					echo "Unknown option --${OPTARG}" >&2
				fi
				;;
			esac
			;;
		h)
			usage
			exit 2
			;;
		*)
			if [ "$OPTERR" != 1 ] || [ "${OPT_SPEC:0:1}" = ":" ]; then
				echo "Non-option argument: '-${OPTARG}'" >&2
			fi
			;;
		esac
	done
}

parseOpts "$@"

if [ -z "$PKG_URL" ]; then
	echo "ERROR: --pkgurl option not provided."
	usage
fi

if [ -z "$INS_DIR" ]; then
	INS_DIR="/opt/tagent"
fi

if [ -z "$USER_RUNON" ]; then
	USER_RUNON="root"
fi

if [ -z "$PORT" ]; then
	PORT="3939"
fi

if [ -z "$TENANT" ]; then
	TENANT="test"
fi

#是否安装perl
echo "INFO: Check perl runtime environment..."
which perl
if [ $? != 0 ]; then
	echo "ERROR: Perl runtime not exists, tagent is dependened on perl, please install it, exit."
	exit 2
fi

#检查是否安装curl
which curl
if [ $? = 0 ]; then
	echo "INFO: curl is ready."

	#下载压缩包  http  or 本地压缩包
	echo "INFO: curl download install package from $PKG_URL....."
	if [ -z "$DOWNLOAD_CRED" ]; then
		curl -o /tmp/tagent.tar $PKG_URL
	else
		curl -o /tmp/tagent.tar --user "$DOWNLOAD_USER:$DOWNLOAD_PWD" "$PKG_URL"
	fi

	if [ $? != 0 ]; then
		echo "ERROR:Download install package file from '$PKG_URL' failed."
		exit 3
	fi
else
	which wget
	if [ $? = 0 ]; then
		echo "INFO: wget download install package from '$PKG_URL'....."
		if [ -z "$DOWNLOAD_CRED" ]; then
			wget -O /tmp/tagent.tar "$PKG_URL"
		else
			wget -O /tmp/tagent.tar --user="$DOWNLOAD_USER" --password="$DOWNLOAD_PWD" "$PKG_URL"
		fi

		if [ $? != 0 ]; then
			echo "ERROR:Download install package file from '$PKG_URL' failed."
			exit 3
		fi
	else
		echo "ERROR: Can not find curl or wget to download install package, install failed."
	fi
fi

if [ ! -e "$INS_DIR" ]; then
	mkdir -p "$INS_DIR"
fi

# tagent 压缩包解压
echo "INFO:Extract Package"
tar xvf /tmp/tagent.tar -C "$INS_DIR"
if [ $? = 0 ]; then
	echo "INFO: Extract tagent package success."
else
	echo "ERROR: Extract tagent package failed."
	exit 4
fi

cd "$INS_DIR/bin" && ./setup.sh --action install --tenant "$TENANT" --serveraddr "$SRV_ADDR" --user "$USER_RUNON" --listenaddr "$LISTEN_ADDR" --port "$PORT"

if [ $? = 0 ]; then
	echo "INFO: Tagent install success."
else
	echo "INFO: Tagent install failed."
	exit $?
fi
