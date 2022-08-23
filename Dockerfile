# JAVA BASE IMAGE -- START
FROM ubuntu:22.04

ENV JAVA_HOME /opt/java/openjdk
ENV PATH $JAVA_HOME/bin:$PATH

# Default to UTF-8 file.encoding
ENV LANG='en_US.UTF-8' LANGUAGE='en_US:en' LC_ALL='en_US.UTF-8'

RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends tzdata curl wget ca-certificates fontconfig locales \
  && echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen \
  && locale-gen en_US.UTF-8 \
  && rm -rf /var/lib/apt/lists/*

ENV JAVA_VERSION jdk8u345-b01

RUN set -eux; \
  ARCH="$(dpkg --print-architecture)"; \
  case "${ARCH}" in \
  aarch64|arm64) \
  ESUM='c1965fb24dded7d7944e2da36cd902adf3b7b1d327aaa21ea507cff00a5a0090'; \
  BINARY_URL='https://github.com/adoptium/temurin8-binaries/releases/download/jdk8u345-b01/OpenJDK8U-jdk_aarch64_linux_hotspot_8u345b01.tar.gz'; \
  ;; \
  armhf|arm) \
  ESUM='af4ecd311df32b405142d5756f966418d0200fbf6cb9009c20a44dc691e8da6f'; \
  BINARY_URL='https://github.com/adoptium/temurin8-binaries/releases/download/jdk8u345-b01/OpenJDK8U-jdk_arm_linux_hotspot_8u345b01.tar.gz'; \
  # Fixes libatomic.so.1: cannot open shared object file
  apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends libatomic1 \
  && rm -rf /var/lib/apt/lists/* \
  ;; \
  ppc64el|powerpc:common64) \
  ESUM='f2be72678f6c2ad283453d0e21a6cb03144dda356e4edf79f818d99c37feaf34'; \
  BINARY_URL='https://github.com/adoptium/temurin8-binaries/releases/download/jdk8u345-b01/OpenJDK8U-jdk_ppc64le_linux_hotspot_8u345b01.tar.gz'; \
  ;; \
  amd64|i386:x86-64) \
  ESUM='ed6c9db3719895584fb1fd69fc79c29240977675f26631911c5a1dbce07b7d58'; \
  BINARY_URL='https://github.com/adoptium/temurin8-binaries/releases/download/jdk8u345-b01/OpenJDK8U-jdk_x64_linux_hotspot_8u345b01.tar.gz'; \
  ;; \
  *) \
  echo "Unsupported arch: ${ARCH}"; \
  exit 1; \
  ;; \
  esac; \
  wget -O /tmp/openjdk.tar.gz ${BINARY_URL}; \
  echo "${ESUM} */tmp/openjdk.tar.gz" | sha256sum -c -; \
  mkdir -p "$JAVA_HOME"; \
  tar --extract \
  --file /tmp/openjdk.tar.gz \
  --directory "$JAVA_HOME" \
  --strip-components 1 \
  --no-same-owner \
  ; \
  rm /tmp/openjdk.tar.gz; \
  # https://github.com/docker-library/openjdk/issues/331#issuecomment-498834472
  find "$JAVA_HOME/lib" -name '*.so' -exec dirname '{}' ';' | sort -u > /etc/ld.so.conf.d/docker-openjdk.conf; \
  ldconfig;

RUN echo Verifying install ... \
  && echo javac -version && javac -version \
  && echo java -version && java -version \
  && echo Complete.

# JAVA BASE IMAGE -- END

# JUPYTER IMAGE -- START

LABEL maintainer="Jupyter Project <jupyter@googlegroups.com>"
ARG DB_CONNECT_VERSION="9.1.*"
ARG NB_USER="viniro"
ARG NB_UID="1000"
ARG NB_GID="100"

# Fix: https://github.com/hadolint/hadolint/wiki/DL4006
# Fix: https://github.com/koalaman/shellcheck/wiki/SC3014
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

USER root

# Install all OS dependencies for notebook server that starts but lacks all
# features (e.g., download as all possible file formats)
ENV DEBIAN_FRONTEND noninteractive
RUN apt-get update --yes && \
  # - apt-get upgrade is run to patch known vulnerabilities in apt-get packages as
  #   the ubuntu base image is rebuilt too seldom sometimes (less than once a month)
  apt-get upgrade --yes && \
  apt-get install --yes --no-install-recommends \
  # - bzip2 is necessary to extract the micromamba executable.
  bzip2 \
  ca-certificates \
  fonts-liberation \
  locales \
  # - pandoc is used to convert notebooks to html files
  #   it's not present in arm64 ubuntu image, so we install it here
  pandoc \
  # - run-one - a wrapper script that runs no more
  #   than one unique  instance  of  some  command with a unique set of arguments,
  #   we use `run-one-constantly` to support `RESTARTABLE` option
  run-one \
  sudo \
  # - tini is installed as a helpful container entrypoint that reaps zombie
  #   processes and such of the actual executable we want to start, see
  #   https://github.com/krallin/tini#why-tini for details.
  tini \
  wget && \
  apt-get clean && rm -rf /var/lib/apt/lists/* && \
  echo "en_US.UTF-8 UTF-8" > /etc/locale.gen && \
  locale-gen

# Configure environment
ENV CONDA_DIR=/opt/conda \
  SHELL=/bin/bash \
  NB_USER="${NB_USER}" \
  NB_UID=${NB_UID} \
  NB_GID=${NB_GID} \
  LC_ALL=en_US.UTF-8 \
  LANG=en_US.UTF-8 \
  LANGUAGE=en_US.UTF-8
ENV PATH="${CONDA_DIR}/bin:${PATH}" \
  HOME="/home/${NB_USER}"

# Copy a script that we will use to correct permissions after running certain commands
COPY fix-permissions /usr/local/bin/fix-permissions
RUN chmod a+rx /usr/local/bin/fix-permissions

# Enable prompt color in the skeleton .bashrc before creating the default NB_USER
# hadolint ignore=SC2016
RUN sed -i 's/^#force_color_prompt=yes/force_color_prompt=yes/' /etc/skel/.bashrc && \
  # Add call to conda init script see https://stackoverflow.com/a/58081608/4413446
  echo 'eval "$(command conda shell.bash hook 2> /dev/null)"' >> /etc/skel/.bashrc

# Create NB_USER with name viniro user with UID=1000 and in the 'users' group
# and make sure these dirs are writable by the `users` group.
RUN echo "auth requisite pam_deny.so" >> /etc/pam.d/su && \
  sed -i.bak -e 's/^%admin/#%admin/' /etc/sudoers && \
  sed -i.bak -e 's/^%sudo/#%sudo/' /etc/sudoers && \
  useradd -l -m -s /bin/bash -N -u "${NB_UID}" "${NB_USER}" && \
  mkdir -p "${CONDA_DIR}" && \
  chown "${NB_USER}:${NB_GID}" "${CONDA_DIR}" && \
  chmod g+w /etc/passwd && \
  fix-permissions "${HOME}" && \
  fix-permissions "${CONDA_DIR}"

USER ${NB_UID}

# Pin python version here, or set it to "default"
ARG PYTHON_VERSION=3.10

# Setup work directory for backward-compatibility
RUN mkdir "/home/${NB_USER}/work" && \
  fix-permissions "/home/${NB_USER}"

# Download and install Micromamba, and initialize Conda prefix.
#   <https://github.com/mamba-org/mamba#micromamba>
#   Similar projects using Micromamba:
#     - Micromamba-Docker: <https://github.com/mamba-org/micromamba-docker>
#     - repo2docker: <https://github.com/jupyterhub/repo2docker>
# Install Python, Mamba, Jupyter Notebook, Lab, and Hub
# Generate a notebook server config
# Cleanup temporary files and remove Micromamba
# Correct permissions
# Do all this in a single RUN command to avoid duplicating all of the
# files across image layers when the permissions change
COPY --chown="${NB_UID}:${NB_GID}" initial-condarc "${CONDA_DIR}/.condarc"
WORKDIR /tmp
RUN set -x && \
  arch=$(uname -m) && \
  if [ "${arch}" = "x86_64" ]; then \
  # Should be simpler, see <https://github.com/mamba-org/mamba/issues/1437>
  arch="64"; \
  fi && \
  wget -qO /tmp/micromamba.tar.bz2 \
  "https://micromamba.snakepit.net/api/micromamba/linux-${arch}/latest" && \
  tar -xvjf /tmp/micromamba.tar.bz2 --strip-components=1 bin/micromamba && \
  rm /tmp/micromamba.tar.bz2 && \
  PYTHON_SPECIFIER="python=${PYTHON_VERSION}" && \
  if [[ "${PYTHON_VERSION}" == "default" ]]; then PYTHON_SPECIFIER="python"; fi && \
  # Install the packages
  ./micromamba install \
  --root-prefix="${CONDA_DIR}" \
  --prefix="${CONDA_DIR}" \
  --yes \
  "${PYTHON_SPECIFIER}" \
  'mamba' \
  'notebook' \
  'jupyterhub' \
  'jupyterlab' && \
  rm micromamba && \
  # Pin major.minor version of python
  mamba list python | grep '^python ' | tr -s ' ' | cut -d ' ' -f 1,2 >> "${CONDA_DIR}/conda-meta/pinned" && \
  jupyter notebook --generate-config && \
  mamba clean --all -f -y && \
  npm cache clean --force && \
  jupyter lab clean && \
  rm -rf "/home/${NB_USER}/.cache/yarn" && \
  fix-permissions "${CONDA_DIR}" && \
  fix-permissions "/home/${NB_USER}"

EXPOSE 8888

# Configure container startup
ENTRYPOINT ["tini", "-g", "--"]
CMD ["start-notebook.sh"]

# Copy local files as late as possible to avoid cache busting
COPY start.sh start-notebook.sh start-singleuser.sh /usr/local/bin/
# Currently need to have both jupyter_notebook_config and jupyter_server_config to support classic and lab
COPY jupyter_server_config.py /etc/jupyter/

# Fix permissions on /etc/jupyter as root
USER root

# Legacy for Jupyter Notebook Server, see: [#1205](https://github.com/jupyter/docker-stacks/issues/1205)
RUN sed -re "s/c.ServerApp/c.NotebookApp/g" \
  /etc/jupyter/jupyter_server_config.py > /etc/jupyter/jupyter_notebook_config.py && \
  fix-permissions /etc/jupyter/

# HEALTHCHECK documentation: https://docs.docker.com/engine/reference/builder/#healthcheck
# This healtcheck works well for `lab`, `notebook`, `nbclassic`, `server` and `retro` jupyter commands
# https://github.com/jupyter/docker-stacks/issues/915#issuecomment-1068528799
HEALTHCHECK  --interval=15s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -O- --no-verbose --tries=1 --no-check-certificate \
  http${GEN_CERT:+s}://localhost:8888${JUPYTERHUB_SERVICE_PREFIX:-/}api || exit 1

# Switch back to viniro to avoid accidental container runs as root
USER ${NB_UID}

# JUPYTER IMAGE -- END

RUN sh -c "pip install psycopg2-binary==2.9.1 lxml==4.9.1 databricks-connect==${DB_CONNECT_VERSION}"

WORKDIR "${HOME}"