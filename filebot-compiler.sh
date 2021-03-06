#!/bin/bash

# Name: Filebot Compiler
# Description: Compile latest commit Filebot project (by rednoah)
# Author: Ivan Alejandro Marugan (hello@ialejandro.rocks)

set -e -u


# COLOR MESSAGES
OK=$(tput setaf 2)
WARN=$(tput setaf 3)
ERR=$(tput setaf 1)
NC=$(tput sgr0)

# VARS
LOGDIR="${HOME}/build_log_filebot"
LOGFILE="${LOGDIR}/filebot_$(date +%d_%m_%Y).log"

# PARAMS
APACHE_IVY_FILE="http://ant.apache.org/ivy/history/latest-milestone/samples/build.xml"
APACHE_IVY_SOURCE="${HOME}/apache-ivy"
FILEBOT_CONFIG="${HOME}/.filebot"
FILEBOT_SOURCE="${HOME}/filebot"
FILEBOT_API="https://api.github.com/repos/filebot/filebot"
FILEBOT_REPO="https://github.com/filebot/filebot.git"
SLF4J_API_VERSION="1.7.9"

# Dirs and persistence commits
create_dirs() {
	# Config dir
	if [[ ! -d "${FILEBOT_CONFIG}" ]]; then
		mkdir -p "${FILEBOT_CONFIG}"
	fi

	# Commits file persistence
	if [[ ! -f "${FILEBOT_CONFIG}/commits_versions" ]]; then
		touch "${FILEBOT_CONFIG}/commits_versions"
	fi

	# Log dir
	if [[ ! -d "${LOGDIR}" ]]; then
		mkdir -p "${LOGDIR}"
	fi
}

# Packages necessary to compile
install_packages() {
	PACKAGES="jq git curl ant"
	# USER WITH PRIVILEGES
	if [[ ${EUID} != 0 ]]; then
		echo "[${WARN}WARNING${NC}] You need root privileges to update and install packages: ${PACKAGES}. Enter you password to continue:"
	fi

	# Update repositories
	su - root -c "apt-get -q=2 update"

	# Packages
	for SOFT in $PACKAGES; do
		EXISTS=$(which ${SOFT} >/dev/null; echo $?)
		if [[ ${EXISTS} != 0 ]]; then
			echo "[${WARN}WARNING${NC}] ${SOFT} isn't installed. Installing..." 
			su - root -c "apt-get -qq install ${SOFT}" &>/dev/null
		else
			echo "[${OK}OK${NC}] ${SOFT} installed." 
		fi
	done

	# Java packages (OpenJDK and OpenJFX)
	#EXISTS=$(dpkg -l | grep openjdk-8-jdk >/dev/null; echo $?)
	#if [[ ${EXISTS} != 0 ]]; then
	#	echo "[${WARN}WARNING${NC}] open-jdk and openjfx aren't installed. Installing..." 
	#	su - root -c "apt-get -qq install openjdk-8-jdk openjfx" &>/dev/null
	#else
	#	echo "[${OK}OK${NC}] open-jdk and openjfx installed." 
	#fi

	# Apache Ivy
	EXISTS=$(ls /usr/share/ant/lib/ivy.jar &>/dev/null; echo $?)
	if [[ ${EXISTS} != 0 ]]; then
		# Download latest Apache Ivy
		mkdir -p "${APACHE_IVY_SOURCE}"
		echo "[${OK}OK${NC}] Download new changes in Apache Ivy repository..."
		wget -qP "${APACHE_IVY_SOURCE}" "${APACHE_IVY_FILE}"
		ant -S -buildfile "${APACHE_IVY_SOURCE}"
		mv "${APACHE_IVY_SOURCE}/ivy/ivy.jar" "/usr/share/ant/lib/"
	fi
}

# Download filebot repository
download() {
	# Download repo or new changes
	if [[ -d ${FILEBOT_SOURCE} ]]; then
		echo "[${OK}OK${NC}] Download new changes in Filebot repository..." 
		git --git-dir="${FILEBOT_SOURCE}/.git" pull -q ${FILEBOT_REPO}
	else
		echo "[${OK}OK${NC}] Download Filebot repository..." 
		git clone -q ${FILEBOT_REPO} ${FILEBOT_SOURCE}
	fi
	
	# Check download
	if [[ ! -d ${FILEBOT_SOURCE} ]]; then
		echo "[${ERR}ERROR${NC}] Download Filebot repository failed!." 
		exit 1
	fi
}

# Install dependencies (ivy.xml and slfj4)
install_dependencies() {
	echo "[${OK}OK${NC}] Downloads Filebot project dependencies..."  
	# Download dependencies ivy.xml
	ant -S -logfile ${LOGDIR}/apache_ant_$(date +%d_%m_%Y).log resolve -buildfile "${FILEBOT_SOURCE}" &>/dev/null

	# Download slf4j-api and move
	if [[ ! -f "${FILEBOT_SOURCE}/dist/lib/slf4j-api.jar" ]]; then
		wget -qO /tmp/slf4j-api.jar http://central.maven.org/maven2/org/slf4j/slf4j-api/${SLF4J_API_VERSION}/slf4j-api-${SLF4J_API_VERSION}.jar
		mkdir -p "${FILEBOT_SOURCE}/dist/lib/" "${FILEBOT_SOURCE}/lib/ivy/source/" "${FILEBOT_SOURCE}/lib/ivy/jar/" "${FILEBOT_SOURCE}/lib/ivy/javadoc/"
		cp /tmp/slf4j-api.jar "${FILEBOT_SOURCE}/dist/lib/"
		cp /tmp/slf4j-api.jar "${FILEBOT_SOURCE}/lib/ivy/source/"
		cp /tmp/slf4j-api.jar "${FILEBOT_SOURCE}/lib/ivy/jar/"
		cp /tmp/slf4j-api.jar "${FILEBOT_SOURCE}/lib/ivy/javadoc/"
		rm -rf /tmp/slf4j-api.jar
	fi
}

# Compile Filebot
compile() {
	COMMIT=$(echo ${1:0:7})
	echo "[${OK}OK${NC}] Compiling Filebot (${COMMIT})..." 

	# Compile starts
	ant -S -logfile ${LOGDIR}/apache_ant_$(date +%d_%m_%Y).log -buildfile "${FILEBOT_SOURCE}" &>/dev/null

	# Check compile
	if [[ -d ${HOME}/filebot ]]; then
	        cp ${FILEBOT_SOURCE}/dist/*.jar "${FILEBOT_SOURCE}/dist/Filebot.jar"
		VERSION=$(java -jar "${FILEBOT_SOURCE}/dist/Filebot.jar" -version | awk '{ print $2 }')
		mv "${FILEBOT_SOURCE}/dist/Filebot.jar" "${HOME}/Filebot_${VERSION}_(${COMMIT}).jar"

		# Success and clean Apache Ant build
		ant clean -S -buildfile "${FILEBOT_SOURCE}"
		summary "${HOME}/Filebot_${VERSION}_(${COMMIT}).jar" "${VERSION}" "${COMMIT}"
	else
		# Fail
		ant clean -S -buildfile "${FILEBOT_SOURCE}"
		summary 1
	fi
}

# Summary
summary() {
	echo ""
	if [[ -f "${1}" ]]; then
		echo "- Compile: ${OK}Success!${NC}"
		echo "- Version: Filebot ${2} (${3})"
		echo "- File path: ${1}"
	elif [[ ${1} != 0 ]]; then
		echo "- Compile: ${ERR}Failed!${NC}. Please check logs (${LOGDIR})."
		exit 1
	fi
}

# Remove dirs
remove_dirs() {
	echo "[${WARN}WARNING${NC}] Remove dir ${FILEBOT_SOURCE}..." 
	rm -rf "${FILEBOT_SOURCE}"
}

###################### MAIN

install_packages
create_dirs

NEW_REV=$(curl -s -H 'Accept: application/vnd.github.v3+json' ${FILEBOT_API}/commits | jq -r .[0].sha)
LAST_REV=$(cat "${FILEBOT_CONFIG}/commits_versions")

# Compile if last commit is different
if [[ "${NEW_REV}" != "${LAST_REV}" ]]; then
	download
	install_dependencies
	compile ${NEW_REV}

	# Save commit version
	echo "${NEW_REV}" > "${FILEBOT_CONFIG}/commits_versions"
else
	echo "[${WARN}WARNING${NC}] This version has been compiled."
fi
