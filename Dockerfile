# Copyright (c) Jupyter Development Team.
# Distributed under the terms of the Modified BSD License.

# Ubuntu 20.04 (focal)
# https://hub.docker.com/_/ubuntu/?tab=tags&name=focal
# OS/ARCH: linux/amd64
ARG ROOT_CONTAINER=ubuntu:focal-20210416@sha256:86ac87f73641c920fb42cc9612d4fb57b5626b56ea2a19b894d0673fd5b4f2e9

ARG BASE_CONTAINER=$ROOT_CONTAINER
FROM $BASE_CONTAINER

LABEL maintainer="Jupyter Project <jupyter@googlegroups.com>"
ARG NB_USER="athena"
ARG NB_UID="1000820000"
ARG NB_GID="1000820000"

# Fix DL4006
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

USER root

# ---- Miniforge installer ----
# Default values can be overridden at build time
# (ARGS are in lower case to distinguish them from ENV)
# Check https://github.com/conda-forge/miniforge/releases
# Conda version
ARG conda_version="4.8.3"
# Miniforge installer patch version
ARG miniforge_patch_number="5"
# Miniforge installer architecture
ARG miniforge_arch="x86_64"
# Package Manager and Python implementation to use (https://github.com/conda-forge/miniforge)
# - conda only: either Miniforge3 to use Python or Miniforge-pypy3 to use PyPy
# - conda + mamba: either Mambaforge to use Python or Mambaforge-pypy3 to use PyPy
ARG miniforge_python="Miniforge3"

# Miniforge archive to install
ARG miniforge_version="${conda_version}-${miniforge_patch_number}"
# Miniforge installer
ARG miniforge_installer="${miniforge_python}-${miniforge_version}-Linux-${miniforge_arch}.sh"
# Miniforge checksum
ARG miniforge_checksum="cb8e6901051978498ed99fb936ae284e2e63fc512bac1787e9229031163da9b4"
ARG openjdk_version="11"

# Install all OS dependencies for notebook server that starts but lacks all
# features (e.g., download as all possible file formats)
ENV DEBIAN_FRONTEND noninteractive
RUN apt-get -q update && \
    apt-get install -yq --no-install-recommends \
    tini \
    wget \
    ca-certificates \
    sudo \
    locales \
    fonts-liberation \
    run-one \
    python3-dev \
    build-essential \
    telnet \
    vim-tiny && \
    apt-get clean && rm -rf /var/lib/apt/lists/*
RUN apt-get -q update && \
    apt-get install -yq --no-install-recommends \
    git \
    dnsutils \
    iputils-ping \
    inkscape \
    libsm6 \
    libxext-dev \
    libxrender1 &&\
    apt-get clean && rm -rf /var/lib/apt/lists/*
RUN apt-get -q update && \
    apt-get install -yq --no-install-recommends \
    lmodern \
    netcat \
    texlive-xetex \
    texlive-fonts-recommended \
    texlive-plain-generic \
    tzdata \
    unzip \
    nano-tiny && \
    apt-get clean && rm -rf /var/lib/apt/lists/*
RUN apt-get -q update && \
    apt-get install -y --no-install-recommends \
    ffmpeg \
    dvipng && \
    apt-get clean && rm -rf /var/lib/apt/lists/*
RUN apt-get -q update && \
    apt-get install -y \
    cm-super \
    "openjdk-${openjdk_version}-jre-headless" \
    ca-certificates-java \
    tesseract-ocr \
    tesseract-ocr-tur \
    imagemagick \
    libaio-dev && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

RUN echo "en_US.UTF-8 UTF-8" > /etc/locale.gen && \
    locale-gen

# Configure environment
ENV CONDA_DIR=/opt/conda \
    SHELL=/bin/bash \
    NB_USER=$NB_USER \
    NB_UID=$NB_UID \
    NB_GID=$NB_GID \
    LC_ALL=en_US.UTF-8 \
    LANG=en_US.UTF-8 \
    LANGUAGE=en_US.UTF-8
ENV PATH=$CONDA_DIR/bin:$PATH \
    HOME=/home/$NB_USER \
    CONDA_VERSION="${conda_version}" \
    MINIFORGE_VERSION="${miniforge_version}"

# Copy a script that we will use to correct permissions after running certain commands
COPY fix-permissions /usr/local/bin/fix-permissions
RUN chmod a+rx /usr/local/bin/fix-permissions

# Enable prompt color in the skeleton .bashrc before creating the default NB_USER
# hadolint ignore=SC2016
RUN sed -i 's/^#force_color_prompt=yes/force_color_prompt=yes/' /etc/skel/.bashrc && \
   # Add call to conda init script see https://stackoverflow.com/a/58081608/4413446
   echo 'eval "$(command conda shell.bash hook 2> /dev/null)"' >> /etc/skel/.bashrc 

# Create NB_USER with name jovyan user with UID=1000 and in the 'users' group
# and make sure these dirs are writable by the `users` group.
RUN echo "auth requisite pam_deny.so" >> /etc/pam.d/su && \
    sed -i.bak -e 's/^%admin/#%admin/' /etc/sudoers && \
    sed -i.bak -e 's/^%sudo/#%sudo/' /etc/sudoers && \
    groupmod -g $NB_GID users && \
    useradd -m -s /bin/bash -g $NB_GID -l -u $NB_UID $NB_USER && \
    mkdir -p $CONDA_DIR && \
    chown $NB_USER:$NB_GID $CONDA_DIR && \
    chmod g+w /etc/passwd && \
    fix-permissions ${HOME} && \
    fix-permissions ${CONDA_DIR}

USER $NB_UID
ARG PYTHON_VERSION=default

# Setup work directory for backward-compatibility
RUN mkdir "/home/$NB_USER/work" && \
    fix-permissions "/home/${NB_USER}"

# Install conda as jovyan and check the sha256 sum provided on the download site
WORKDIR /tmp

# Prerequisites installation: conda, mamba, pip, tini
RUN wget --quiet "https://github.com/conda-forge/miniforge/releases/download/${miniforge_version}/${miniforge_installer}" && \
    echo "${miniforge_checksum} *${miniforge_installer}" | sha256sum --check && \
    /bin/bash "${miniforge_installer}" -f -b -p $CONDA_DIR && \
    rm "${miniforge_installer}" && \
    # Conda configuration see https://conda.io/projects/conda/en/latest/configuration.html
    echo "conda ${CONDA_VERSION}" >> $CONDA_DIR/conda-meta/pinned && \
    conda config --system --set auto_update_conda false && \
    conda config --system --set show_channel_urls true && \
    if [ ! $PYTHON_VERSION = 'default' ]; then conda install --yes python=$PYTHON_VERSION; fi && \
    conda list python | grep '^python ' | tr -s ' ' | cut -d '.' -f 1,2 | sed 's/$/.*/' >> $CONDA_DIR/conda-meta/pinned && \
    conda install --quiet --yes \
    "conda=${CONDA_VERSION}" \
    'pip' && \
    conda update --all --quiet --yes && \
    conda clean --all -f -y && \
    rm -rf /home/$NB_USER/.cache/yarn && \
    fix-permissions ${CONDA_DIR} && \
    fix-permissions /home/${NB_USER}

# Install Jupyter Notebook, Lab, and Hub
# Generate a notebook server config
# Cleanup temporary files
# Correct permissions
# Do all this in a single RUN command to avoid duplicating all of the
# files across image layers when the permissions change
RUN conda install --quiet --yes \
    'notebook=6.4.0' \
    'jupyterhub=1.4.1' \
    'jupyterlab=3.0.16' && \
    conda clean --all -f -y && \
    npm cache clean --force && \
    jupyter notebook --generate-config && \
    jupyter lab clean && \
    rm -rf /home/$NB_USER/.cache/yarn && \
    fix-permissions ${CONDA_DIR} && \
    fix-permissions /home/${NB_USER}

# Copy local files as late as possible to avoid cache busting
COPY start.sh start-notebook.sh start-singleuser.sh /usr/local/bin/
# Currently need to have both jupyter_notebook_config and jupyter_server_config to support classic and lab
COPY jupyter_notebook_config.py /etc/jupyter/

# Fix permissions on /etc/jupyter as root
USER root

# Prepare upgrade to JupyterLab V3.0 #1205
RUN sed -re "s/c.NotebookApp/c.ServerApp/g" \
    /etc/jupyter/jupyter_notebook_config.py > /etc/jupyter/jupyter_server_config.py

RUN fix-permissions /etc/jupyter/

# Create alternative for nano -> nano-tiny
RUN update-alternatives --install /usr/bin/nano nano /bin/nano-tiny 10

USER $NB_UID

# Install Python 3 conda packages
RUN conda install --quiet --yes \
    'altair=4.1.*' \
    'beautifulsoup4=4.9.*' \
    'bokeh=2.3.*' \
    'bottleneck=1.3.*' \
    'cloudpickle=1.6.*' \
    'conda-forge::blas=*=openblas' \
    'cython=0.29.*' \
    'dask=2021.4.*' \
    'dill=0.3.*' \
    'h5py=3.2.*' && \
    conda clean --all -f -y && \
    rm -rf /home/$NB_USER/.cache/yarn && \
    fix-permissions "${CONDA_DIR}" && \
    fix-permissions "/home/${NB_USER}"
RUN conda install --quiet --yes \
    'ipympl=0.7.*' \
    'ipywidgets=7.6.*' \
    'matplotlib-base=3.4.*' \
    'numba=0.53.*' \
    'numexpr=2.7.*' \
    'pandas=1.2.*' \
    'patsy=0.5.*' \
    'protobuf=3.15.*' && \
    conda clean --all -f -y && \
    rm -rf /home/$NB_USER/.cache/yarn && \
    fix-permissions "${CONDA_DIR}" && \
    fix-permissions "/home/${NB_USER}"
RUN conda install --quiet --yes \
    'pytables=3.6.*' \
    'scikit-image=0.18.*' \
    'scikit-learn=0.24.*' \
    'scipy=1.6.*' \
    'seaborn=0.11.*' \
    'sqlalchemy=1.4.*' \
    'statsmodels=0.12.*' && \
    conda clean --all -f -y && \
    rm -rf /home/$NB_USER/.cache/yarn && \
    fix-permissions "${CONDA_DIR}" && \
    fix-permissions "/home/${NB_USER}"
RUN conda install --quiet --yes \
    'sympy=1.8.*' \
    'widgetsnbextension=3.5.*'\
    'xlrd=2.0.*' \
    'cx_oracle=8.2.0' \
    'boto3=1.17.*' \
    'pyarrow=4.0.*' \
    'plotly=4.14.*' && \
    conda clean --all -f -y && \
    rm -rf /home/$NB_USER/.cache/yarn && \
    fix-permissions "${CONDA_DIR}" && \
    fix-permissions "/home/${NB_USER}"
RUN conda install --quiet --yes \
    'openpyxl' \
    'xlsxwriter' \
    'xgboost' \
    'catboost' && \
    conda clean --all -f -y && \
    rm -rf /home/$NB_USER/.cache/yarn && \
    fix-permissions "${CONDA_DIR}" && \
    fix-permissions "/home/${NB_USER}"
RUN conda install --quiet --yes \
    'hyperopt' \
    'lime' \
    'eli5' \
    'shap' \
    'dash' \
    'lz4' \
    'python-blosc' \
    'jupyter_bokeh' \
    'pdfminer' \
    'pep8' \
    'Pillow' \
    'pkginfo' \
    'pylint' \
    'pytesseract' \
    'pytest' \
    'pytest-astropy' \
    'pyzbar' \
    'sklearn2pmml' \
    'sortedcollections' \
    'Sphinx' \
    'wordcloud' \
    'yellowbrick' \
    'zbar' \
    'xarray' && \
    conda install -c anaconda ephem && \
    conda clean --all -f -y && \
    rm -rf /home/$NB_USER/.cache/yarn && \
    fix-permissions "${CONDA_DIR}" && \
    fix-permissions "/home/${NB_USER}"
RUN conda install -c conda-forge pystan && \
    conda install -c conda-forge fbprophet && \
    conda clean --all -f -y && \
    rm -rf /home/$NB_USER/.cache/yarn && \
    fix-permissions "${CONDA_DIR}" && \
    fix-permissions "/home/${NB_USER}"
RUN conda install --quiet --yes \
    'tensorflow=2.4.1' && \
    rm -rf /home/$NB_USER/.cache/yarn && \
    fix-permissions "${CONDA_DIR}" && \
    fix-permissions "/home/${NB_USER}"

# Install Python 3 pip packages
RUN pip install --no-cache-dir \
    pyspark && \
    rm -rf /home/$NB_USER/.cache/pip/http && \
    fix-permissions "${CONDA_DIR}" && \
    fix-permissions "/home/${NB_USER}"
RUN pip install --no-cache-dir \
    pandas_profiling \
    jupyter-tensorboard
    trino \
    scikit-optimize \
    impyute \ 
    nltk \
    dash-bootstrap-components \
    cufflinks \
    dataframe-image \ 
    fancyimpute \
    fasttext \
    gensim \
    glob2 \
    ITU-Turkish-NLP-Pipeline-Caller \
    JPype1 \
    kerasplotlib \
    knnimpute \
    lightgbm \
    multidict \
    multiprocess \
    tensorflow-datasets \
    pmdarima \
    opencv-contrib-python \
    lckr-jupyterlab-variableinspector \
    jupyterlab-system-monitor \
    snowballstemmer \
    imbalanced-learn \
    ipyrest \
    ing-theme-matplotlib && \ 
    rm -rf /home/$NB_USER/.cache/pip/http && \
    fix-permissions "${CONDA_DIR}" && \
    fix-permissions "/home/${NB_USER}"
RUN pip install --no-cache-dir torch==1.8.1+cpu torchvision==0.9.1+cpu torchaudio==0.8.1 -f https://download.pytorch.org/whl/torch_stable.html && \ 
    rm -rf /home/$NB_USER/.cache/pip/http && \
    fix-permissions "${CONDA_DIR}" && \
    fix-permissions "/home/${NB_USER}"

# Import matplotlib the first time to build the font cache.
ENV XDG_CACHE_HOME="/home/${NB_USER}/.cache/"

RUN MPLBACKEND=Agg python -c "import matplotlib.pyplot" && \
    fix-permissions "/home/${NB_USER}"

RUN jupyter labextension install jupyterlab-spreadsheet && \
    jupyter labextension install jupyterlab_tensorboard && \
    npm cache clean --force && \
    rm -rf /home/$NB_USER/.cache/yarn

USER root

# Spark dependencies
# Default values can be overridden at build time
# (ARGS are in lower case to distinguish them from ENV)
ARG spark_version="3.1.2"
ARG hadoop_version="3.2"
ARG spark_checksum="2385CB772F21B014CE2ABD6B8F5E815721580D6E8BC42A26D70BBCDDA8D303D886A6F12B36D40F6971B5547B70FAE62B5A96146F0421CB93D4E51491308EF5D5"

ENV APACHE_SPARK_VERSION="${spark_version}" \
    HADOOP_VERSION="${hadoop_version}"

# Spark installation
WORKDIR /tmp
# Using the preferred mirror to download Spark
# hadolint ignore=SC2046
RUN wget -q $(wget -qO- https://www.apache.org/dyn/closer.lua/spark/spark-${APACHE_SPARK_VERSION}/spark-${APACHE_SPARK_VERSION}-bin-hadoop${HADOOP_VERSION}.tgz\?as_json | \
    python -c "import sys, json; content=json.load(sys.stdin); print(content['preferred']+content['path_info'])") && \
    echo "${spark_checksum} *spark-${APACHE_SPARK_VERSION}-bin-hadoop${HADOOP_VERSION}.tgz" | sha512sum -c - && \
    tar xzf "spark-${APACHE_SPARK_VERSION}-bin-hadoop${HADOOP_VERSION}.tgz" -C /usr/local --owner root --group root --no-same-owner && \
    rm "spark-${APACHE_SPARK_VERSION}-bin-hadoop${HADOOP_VERSION}.tgz"

WORKDIR /usr/local

# Configure Spark
ENV SPARK_HOME=/usr/local/spark
ENV SPARK_OPTS="--driver-java-options=-Xms1024M --driver-java-options=-Xmx8192M --driver-java-options=-Dlog4j.logLevel=info" \
    PATH=$PATH:$SPARK_HOME/bin

RUN ln -s "spark-${APACHE_SPARK_VERSION}-bin-hadoop${HADOOP_VERSION}" spark && \
    # Add a link in the before_notebook hook in order to source automatically PYTHONPATH
    mkdir -p /usr/local/bin/before-notebook.d && \
    ln -s "${SPARK_HOME}/sbin/spark-config.sh" /usr/local/bin/before-notebook.d/spark-config.sh

# Fix Spark installation for Java 11 and Apache Arrow library
# see: https://github.com/apache/spark/pull/27356, https://spark.apache.org/docs/latest/#downloading
RUN cp -p "$SPARK_HOME/conf/spark-defaults.conf.template" "$SPARK_HOME/conf/spark-defaults.conf" && \
    echo 'spark.driver.extraJavaOptions -Dio.netty.tryReflectionSetAccessible=true' >> $SPARK_HOME/conf/spark-defaults.conf && \
    echo 'spark.executor.extraJavaOptions -Dio.netty.tryReflectionSetAccessible=true' >> $SPARK_HOME/conf/spark-defaults.conf

# Install Oracle Instant Client 21.1.0.0.0_x64 and sqlplus
COPY instantclient-basic-linux.x64-21.1.0.0.0.zip instantclient-sqlplus-linux.x64-21.1.0.0.0.zip /opt/oracle/
COPY zemberek-full.jar /opt/apps/

RUN unzip /opt/oracle/instantclient-basic-linux.x64-21.1.0.0.0.zip -d /opt/oracle/ && \
    rm /opt/oracle/instantclient-basic-linux.x64-21.1.0.0.0.zip && \
    unzip /opt/oracle/instantclient-sqlplus-linux.x64-21.1.0.0.0.zip -d /opt/oracle/ && \
    rm /opt/oracle/instantclient-sqlplus-linux.x64-21.1.0.0.0.zip && \
    echo "export PATH=/opt/oracle/instantclient_21_1:$PATH" >> /etc/bash.bashrc && \ 
    sh -c "echo /opt/oracle/instantclient_21_1 > /etc/ld.so.conf.d/oracle-instantclient.conf" && \
    ldconfig

USER $NB_UID

WORKDIR $HOME

EXPOSE 8888

# Configure container startup
ENTRYPOINT ["tini", "-g", "--"]
CMD ["start-notebook.sh"]
