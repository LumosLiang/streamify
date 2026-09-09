#!/usr/bin/env bash
set -euo pipefail

SPARK_VERSION="${SPARK_VERSION:-3.5.6}"
SPARK_DIR="${HOME}/spark"
SPARK_HOME="${SPARK_DIR}/spark-${SPARK_VERSION}-bin-hadoop3"

echo "Installing Java 11..."
sudo apt-get update
sudo apt-get install -y openjdk-11-jdk curl tar

echo "Installing Spark ${SPARK_VERSION}..."
mkdir -p "${SPARK_DIR}"
if [[ ! -d "${SPARK_HOME}" ]]; then
	curl -fL "https://dlcdn.apache.org/spark/spark-${SPARK_VERSION}/spark-${SPARK_VERSION}-bin-hadoop3.tgz" \
		| tar -xz -C "${SPARK_DIR}"
fi
PY4J_ZIP="$(find "${SPARK_HOME}/python/lib" -maxdepth 1 -name 'py4j-*.zip' -print -quit)"
if [[ -z "${PY4J_ZIP}" ]]; then
	echo "Could not find Spark's py4j zip file" >&2
	exit 1
fi

cat > "${HOME}/.spark_env" <<EOF
export JAVA_HOME="$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")"
export SPARK_HOME="${SPARK_HOME}"
export PATH="\${JAVA_HOME}/bin:\${SPARK_HOME}/bin:\${SPARK_HOME}/sbin:\${PATH}"
export PYTHONPATH="\${SPARK_HOME}/python:${PY4J_ZIP}:\${PYTHONPATH:-}"
EOF

if ! grep -q 'source "$HOME/.spark_env"' "${HOME}/.bashrc"; then
	printf '\nsource "$HOME/.spark_env"\n' >> "${HOME}/.bashrc"
fi

source "${HOME}/.spark_env"

echo "Java: $(java -version 2>&1 | head -n 1)"
echo "Spark: ${SPARK_HOME}"
echo "Installation complete. Run this script on the master and both workers."