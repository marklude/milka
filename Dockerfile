# Use a Debian/Ubuntu-based image (adjust as needed)
FROM ubuntu:22.04 AS base

# Install system dependencies including build tools and make
RUN apt-get update && apt-get install -y \
    build-essential \
    gfortran \
    pkg-config \
    libopenblas-dev \
    liblapack-dev \
    autoconf \
    automake \
    libtool \
    ninja-build \
    cmake \
    python3 \
    python3-pip \
    && rm -rf /var/lib/apt/lists/*

# (Optional) Upgrade pip if needed
RUN pip3 install --upgrade pip

# Install lightgbm and any other Python packages
# Note: If you installed cmake via apt, you might not need the pip cmake package.
RUN pip3 install --no-cache-dir --no-binary :all: lightgbm==4.2.0

# Setup env
ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONFAULTHANDLER=1 \
    PATH=/home/ftuser/.local/bin:$PATH \
    FT_APP_ENV="docker" \
    PORT=8080 \
    HEALTH_PORT=8081

# Prepare environment
RUN mkdir /freqtrade \
    && apt-get update \
    && apt-get -y install sudo libatlas3-base curl sqlite3 libgomp1 gnupg \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && useradd -u 1000 -G sudo -U -m -s /bin/bash ftuser \
    && chown ftuser:ftuser /freqtrade \
    && echo "ftuser ALL=(ALL) NOPASSWD: /bin/chown" >> /etc/sudoers

WORKDIR /freqtrade

# Copy files with correct ownership
COPY --chown=ftuser:ftuser build_helpers/startup.sh /freqtrade/
COPY --chown=ftuser:ftuser requirements*.txt /freqtrade/

# Install dependencies
FROM base AS python-deps
RUN apt-get update \
    && apt-get -y install --no-install-recommends \
        build-essential \
        libssl-dev \
        git \
        libffi-dev \
        libgfortran5 \
        pkg-config \
        cmake \
        gcc \
        g++ \
        make \
        libomp-dev \
        libboost-all-dev \
        libclang-dev \
        python3-dev \
        ninja-build \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && pip install --no-cache-dir --upgrade pip wheel setuptools

# Install additional build dependencies
RUN apt-get update \
    && apt-get install -y \
        cmake \
        build-essential \
        libboost-dev \
        libboost-system-dev \
        libboost-filesystem-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install TA-lib
COPY build_helpers/* /tmp/
RUN cd /tmp && /tmp/install_ta-lib.sh && rm -r /tmp/*ta-lib*
ENV LD_LIBRARY_PATH=/usr/local/lib

# Install dependencies
COPY --chown=ftuser:ftuser requirements.txt requirements-hyperopt.txt /freqtrade/
USER ftuser
RUN pip install --user --no-cache-dir "numpy<2.0" \
  && pip install --user --no-cache-dir -r requirements-hyperopt.txt \
  && rm -rf /home/ftuser/.cache/pip/**

# Copy dependencies to runtime-image
FROM base AS runtime-image
COPY --from=python-deps /usr/local/lib /usr/local/lib/
ENV LD_LIBRARY_PATH=/usr/local/lib

COPY --from=python-deps --chown=ftuser:ftuser /home/ftuser/.local /home/ftuser/.local/

USER ftuser
# Install and execute
COPY --chown=ftuser:ftuser . /freqtrade/

RUN pip install -e . --user --no-cache-dir --no-build-isolation \
  && freqtrade install-ui \
  && mkdir -p /freqtrade/user_data/data \
  && mkdir -p /freqtrade/user_data/logs \
  && mkdir -p /freqtrade/user_data/strategies \
  && mkdir -p /freqtrade/user_data/hyperopt_results \
  && mkdir -p /freqtrade/user_data/models \
  && mkdir -p /freqtrade/user_data/notebooks \
  && mkdir -p /freqtrade/user_data/plots

# Install FreqAI dependencies one by one to isolate issues
RUN pip install --user --no-cache-dir torch --index-url https://download.pytorch.org/whl/cpu && \
    rm -rf /home/ftuser/.cache/pip/*

RUN pip install --user --no-cache-dir scikit-learn==1.4.0 && \
    rm -rf /home/ftuser/.cache/pip/*

# Install lightgbm with system dependencies
RUN pip install --user --no-cache-dir cmake && \
    pip install --user --no-cache-dir --no-binary :all: lightgbm==4.2.0 && \
    rm -rf /home/ftuser/.cache/pip/*

RUN pip install --user --no-cache-dir xgboost==2.0.3 && \
    pip install --user --no-cache-dir catboost==1.2.2 && \
    rm -rf /home/ftuser/.cache/pip/*

RUN pip install --user --no-cache-dir sb3-contrib datasieve && \
    rm -rf /home/ftuser/.cache/pip/*

# Switch to root for system installations
USER root

# Install Google Cloud SDK with gsutil and crcmod
RUN apt-get update && \
    apt-get install -y \
        apt-transport-https \
        ca-certificates \
        gnupg \
        python3-pip \
        gcc \
        python3-dev && \
    echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | \
    tee -a /etc/apt/sources.list.d/google-cloud-sdk.list && \
    curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | \
    gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg && \
    apt-get update && \
    apt-get install -y google-cloud-sdk google-cloud-sdk-gke-gcloud-auth-plugin && \
    pip install --no-cache-dir -U crcmod && \
    gcloud config set disable_usage_reporting true && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    # Fix permissions for gsutil
    mkdir -p /home/ftuser/.config/gcloud && \
    chown -R ftuser:ftuser /home/ftuser/.config

# Switch back to ftuser
USER ftuser

# Verify gsutil installation and set config
RUN gsutil --version && \
    gcloud config set disable_usage_reporting true

# Install Flask and GCS utilities
RUN pip install --user --no-cache-dir \
    flask \
    requests \
    google-cloud-storage && \
    rm -rf /home/ftuser/.cache/pip/*

# Expose ports
EXPOSE 8080

# Set the startup script as executable
RUN chmod +x /freqtrade/startup.sh

# Run the startup script
CMD ["/freqtrade/startup.sh"]
