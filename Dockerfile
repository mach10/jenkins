# https://hub.docker.com/r/jenkins/jenkins/tags/
FROM jenkins/jenkins:2.179

USER root
RUN apt-get update && apt-get install -y bash git wget openssh-server vim gettext make docker awscli ruby ruby-build python-pip htop libssl-dev libreadline-dev zlib1g-dev ffmpeg build-essential libtool autoconf libjpeg-dev jq
RUN apt-get install -y supervisor

RUN pip install --upgrade pip

# Install pips
ADD requirements.txt /root/requirements.txt
RUN pip install -r /root/requirements.txt

#install pipenv
RUN pip install pipenv

# get and build python 3.6
RUN apt-get install -y libncurses5-dev libncursesw5-dev libsqlite3-dev
RUN apt-get install -y libgdbm-dev libdb5.3-dev libbz2-dev libexpat1-dev liblzma-dev tk-dev
RUN wget https://www.python.org/ftp/python/3.6.1/Python-3.6.1.tar.xz
RUN tar xf Python-3.6.1.tar.xz
RUN cd Python-3.6.1 && ./configure && make -j 8 && make altinstall


# Install m2a-git-mirror
RUN virtualenv /opt/m2a-git-mirror/ -p python3.6
RUN /opt/m2a-git-mirror/bin/pip \
    install git+https://bitbucket.org/m2amedia/m2a-git-mirror.git
RUN ln -s /opt/m2a-git-mirror/bin/m2a-git-mirror /usr/bin

# Install service configurations
COPY supervisor/ /etc/supervisor/conf.d/

# Download terraform binary
ENV TERRAFORM_VERSION=0.11.13
RUN cd /tmp && \
    wget https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip && \
    unzip terraform_${TERRAFORM_VERSION}_linux_amd64.zip -d /usr/bin && \
    rm -rf /tmp/* && \
    rm -rf /var/cache/apk/* && \
    rm -rf /var/tmp/*
RUN terraform -v

# Download packer binary
ENV PACKER_VERSION=1.2.4
RUN cd /tmp && \
    wget https://releases.hashicorp.com/packer/${PACKER_VERSION}/packer_${PACKER_VERSION}_linux_amd64.zip && \
    unzip packer_${PACKER_VERSION}_linux_amd64.zip -d /usr/bin && \
    rm -rf /tmp/* && \
    rm -rf /var/cache/apk/* && \
    rm -rf /var/tmp/*
RUN packer -v

# Add user for managing Git mirrors
ENV GIT_HOME /var/git/
ARG git_user=git
ARG git_group=git
ARG git_uid=1001
ARG git_gid=1001
RUN mkdir -p $GIT_HOME \
  && mkdir $GIT_HOME/.ssh/ \
  && chown -R ${git_uid}:${git_gid} $GIT_HOME \
  && groupadd -g ${git_gid} ${git_group} \
  && useradd \
        -m -d "$GIT_HOME" \
        -u ${git_uid} \
        -g ${git_gid} \
        -s /bin/bash ${git_user}
VOLUME $GIT_HOME/.ssh/
RUN apt-get install -y sudo
ADD sudoers/ /etc/sudoers.d/
RUN chmod 440 /etc/sudoers.d/*

# Allow the jenkins user to run docker
RUN groupadd docker
RUN usermod -aG docker jenkins

# Scripts
ADD scripts /usr/share/jenkins/scripts
RUN chown -R jenkins:jenkins /usr/share/jenkins/scripts
RUN chmod +x /usr/share/jenkins/scripts
RUN chmod +x /usr/share/jenkins/scripts/*
ENV PATH="/usr/share/jenkins/scripts:${PATH}"

# Install h264_analyze
RUN /usr/share/jenkins/scripts/h264-analyze-install

# Install ImageMagick
#RUN /usr/share/jenkins/scripts/magick-install

# Install tesseract
#RUN /usr/share/jenkins/scripts/tesseract-install

# Drop back to the regular jenkins user
USER jenkins

# 1. Disable Jenkins setup Wizard UI. The initial user and password will be supplied by Terraform via ENV vars during infrastructure creation
# 2. Set Java DNS TTL to 60 seconds
# http://docs.aws.amazon.com/sdk-for-java/v1/developer-guide/java-dg-jvm-ttl.html
# http://docs.oracle.com/javase/7/docs/technotes/guides/net/properties.html
# https://aws.amazon.com/articles/4035
# https://stackoverflow.com/questions/29579589/whats-the-recommended-way-to-set-networkaddress-cache-ttl-in-elastic-beanstalk
ENV JAVA_OPTS="-Djenkins.install.runSetupWizard=false -Dhudson.DNSMultiCast.disabled=true -Djava.awt.headless=true -Dsun.net.inetaddr.ttl=60 -Dorg.jenkinsci.plugins.gitclient.Git.timeOut=60"

# Preinstall plugins
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN /usr/local/bin/install-plugins.sh < /usr/share/jenkins/ref/plugins.txt

# Setup Jenkins initial admin user, security mode (Matrix), and the number of job executors
# Many other Jenkins configurations could be done from the Groovy script
COPY init.groovy /usr/share/jenkins/ref/init.groovy.d/

# Configure `Amazon EC2` plugin to start slaves on demand
COPY init-ec2.groovy /usr/share/jenkins/ref/init.groovy.d/

EXPOSE 8080

# Initialise and configure Git mirrors
RUN sudo -u git m2a-git-mirror initialise

# Use Supervisor to run Jenkins and other services. Supervisor will
# handle de-escalating service permissions.
USER root
ENTRYPOINT ["/sbin/tini", "--", "/usr/bin/supervisord", "-n"]
