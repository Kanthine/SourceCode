

export MIGCC="$(xcrun -find cc)"
export MIGCOM="$(xcrun -find migcom)"
export PATH="${PLATFORM_DEVELOPER_BIN_DIR}:${DEVELOPER_BIN_DIR}:${PATH}"
for a in ${ARCHS}; do
	xcrun mig -arch $a -header "${SCRIPT_OUTPUT_FILE_0}" \
			-sheader "${SCRIPT_OUTPUT_FILE_1}" -user /dev/null \
			-server /dev/null "${SCRIPT_INPUT_FILE_0}"
done
