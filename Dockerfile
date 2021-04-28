# --------------------------------------------------
# Overleaf Base Image (sharelatex/sharelatex-base)
# --------------------------------------------------

FROM phusion/baseimage:0.11

ENV baseDir .


# Makes sure LuaTex cache is writable
# -----------------------------------
ENV TEXMFVAR=/var/lib/sharelatex/tmp/texmf-var


# Install dependencies
# --------------------
RUN apt-get update \
&&  apt-get install -y \
      build-essential wget net-tools unzip time imagemagick optipng strace nginx git python zlib1g-dev libpcre3-dev \
      qpdf \
      aspell aspell-en aspell-af aspell-am aspell-ar aspell-ar-large aspell-bg aspell-bn aspell-br aspell-ca aspell-cs aspell-cy aspell-da aspell-de aspell-el aspell-eo aspell-es aspell-et aspell-eu-es aspell-fa aspell-fo aspell-fr aspell-ga aspell-gl-minimos aspell-gu aspell-he aspell-hi aspell-hr aspell-hsb aspell-hu aspell-hy aspell-id aspell-is aspell-it aspell-kk aspell-kn aspell-ku aspell-lt aspell-lv aspell-ml aspell-mr aspell-nl aspell-nr aspell-ns  aspell-pa aspell-pl aspell-pt aspell-pt-br aspell-ro aspell-ru aspell-sk aspell-sl aspell-ss aspell-st aspell-sv aspell-tl aspell-tn aspell-ts aspell-uk aspell-uz aspell-xh aspell-zu \
    \
# install Node.JS 12
&&  curl -sSL https://deb.nodesource.com/setup_12.x | bash - \
&&  apt-get install -y nodejs \
    \
&&  rm -rf \
# We are adding a custom nginx config in the main Dockerfile.
      /etc/nginx/nginx.conf \
      /etc/nginx/sites-enabled/default \
      /var/lib/apt/lists/*

# Add envsubst
# ------------
ADD ./vendor/envsubst /usr/bin/envsubst
RUN chmod +x /usr/bin/envsubst

# Install Grunt
# ------------
RUN npm install -g \
      grunt-cli \
&&  rm -rf /root/.npm

# Install TexLive
# ---------------
# CTAN mirrors occasionally fail, in that case install TexLive against an
# specific server, for example http://ctan.crest.fr
#
# # docker build \
#     --build-arg TEXLIVE_MIRROR=http://ctan.crest.fr/tex-archive/systems/texlive/tlnet \
#     -f Dockerfile-base -t sharelatex/sharelatex-base .
ARG TEXLIVE_MIRROR=http://mirror.ctan.org/systems/texlive/tlnet

ENV PATH "${PATH}:/usr/local/texlive/2021/bin/x86_64-linux"

RUN mkdir /install-tl-unx \
&&  curl -sSL \
      ${TEXLIVE_MIRROR}/install-tl-unx.tar.gz \
    | tar -xzC /install-tl-unx --strip-components=1 \
    \
&&  echo "tlpdbopt_autobackup 0" >> /install-tl-unx/texlive.profile \
&&  echo "tlpdbopt_install_docfiles 0" >> /install-tl-unx/texlive.profile \
&&  echo "tlpdbopt_install_srcfiles 0" >> /install-tl-unx/texlive.profile \
&&  echo "selected_scheme scheme-full" >> /install-tl-unx/texlive.profile \
    \
&&  /install-tl-unx/install-tl \
      -profile /install-tl-unx/texlive.profile \
      -repository ${TEXLIVE_MIRROR} \
    \
&&  tlmgr install --repository ${TEXLIVE_MIRROR} \
      latexmk \
      texcount \
    \
&&  rm -rf /install-tl-unx


# Set up sharelatex user and home directory
# -----------------------------------------
RUN adduser --system --group --home /var/www/sharelatex --no-create-home sharelatex && \
	mkdir -p /var/lib/sharelatex && \
	chown www-data:www-data /var/lib/sharelatex && \
	mkdir -p /var/log/sharelatex && \
	chown www-data:www-data /var/log/sharelatex && \
	mkdir -p /var/lib/sharelatex/data/template_files && \
	chown www-data:www-data /var/lib/sharelatex/data/template_files
	
# ---------------------------------------------
# Overleaf Community Edition (overleaf/overleaf)
# ---------------------------------------------

# ARG SHARELATEX_BASE_TAG=sharelatex/sharelatex-base:latest
# FROM $SHARELATEX_BASE_TAG

ENV SHARELATEX_CONFIG /etc/sharelatex/settings.coffee


# Add required source files
# -------------------------
ADD ${baseDir}/bin /var/www/sharelatex/bin
ADD ${baseDir}/doc /var/www/sharelatex/doc
ADD ${baseDir}/migrations /var/www/sharelatex/migrations
ADD ${baseDir}/tasks /var/www/sharelatex/tasks
ADD ${baseDir}/Gruntfile.coffee /var/www/sharelatex/Gruntfile.coffee
ADD ${baseDir}/package.json /var/www/sharelatex/package.json
ADD ${baseDir}/npm-shrinkwrap.json /var/www/sharelatex/npm-shrinkwrap.json
ADD ${baseDir}/services.js /var/www/sharelatex/config/services.js


# Copy build dependencies
# -----------------------
ADD ${baseDir}/git-revision.sh /var/www/git-revision.sh
ADD ${baseDir}/services.js /var/www/sharelatex/config/services.js


# Checkout services
# -----------------
RUN cd /var/www/sharelatex \
&&    npm install \
&&    grunt install \
  \
# Cleanup not needed artifacts
# ----------------------------
&&  rm -rf /root/.cache /root/.npm $(find /tmp/ -mindepth 1 -maxdepth 1) \
# Stores the version installed for each service
# ---------------------------------------------
&&  cd /var/www \
&&    ./git-revision.sh > revisions.txt \
  \
# Cleanup the git history
# -------------------
&&  rm -rf $(find /var/www/sharelatex -name .git)

# Install npm dependencies
# ------------------------
RUN cd /var/www/sharelatex \
&&    bash ./bin/install-services \
  \
# Cleanup not needed artifacts
# ----------------------------
&&  rm -rf /root/.cache /root/.npm $(find /tmp/ -mindepth 1 -maxdepth 1)

# Compile CoffeeScript
# --------------------
RUN cd /var/www/sharelatex \
&&    bash ./bin/compile-services

# Links CLSI synctex to its default location
# ------------------------------------------
RUN ln -s /var/www/sharelatex/clsi/bin/synctex /opt/synctex


# Copy runit service startup scripts to its location
# --------------------------------------------------
ADD ${baseDir}/runit /etc/service


# Configure nginx
# ---------------
ADD ${baseDir}/nginx/nginx.conf.template /etc/nginx/templates/nginx.conf.template
ADD ${baseDir}/nginx/sharelatex.conf /etc/nginx/sites-enabled/sharelatex.conf


# Configure log rotation
# ----------------------
ADD ${baseDir}/logrotate/sharelatex /etc/logrotate.d/sharelatex
RUN chmod 644 /etc/logrotate.d/sharelatex


# Copy Phusion Image startup scripts to its location
# --------------------------------------------------
COPY ${baseDir}/init_scripts/ /etc/my_init.d/

# Copy app settings files
# -----------------------
COPY ${baseDir}/settings.coffee /etc/sharelatex/settings.coffee

# Set Environment Variables
# --------------------------------
ENV WEB_API_USER "sharelatex"

ENV SHARELATEX_APP_NAME "Overleaf Community Edition - Full Latex Package"

ENV OPTIMISE_PDF "true"

RUN apt-get update && apt-get install -y --no-install-recommends apt-utils

#RUN apt-get install -y texlive-full

RUN apt-get install xzdec

RUN tlmgr init-usertree

RUN tlmgr update --self

RUN tlmgr install scheme-full; exit 0

RUN tlmgr update -all

EXPOSE 80

WORKDIR /

ENTRYPOINT ["/sbin/my_init"]

