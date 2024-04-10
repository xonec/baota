ARG CENTOS_VERSION
ARG NGINX_VERSION
ARG PHP_VERSION
ARG MYSQL_VERSION
FROM centos:${CENTOS_VERSION}
LABEL maintainer="ifui <ifui@foxmail.com>"

RUN groupadd -f www && useradd -g www www

ARG BAOTA_INSTALL_PATH
# install pkg
RUN echo 'bt' > /etc/hostname \
    && yum install -y wget \
    && yum install -y ca-certificates \
    && yum install -y gd
    
# install baota
RUN set -eux \
    && wget -O install.sh ${BAOTA_INSTALL_PATH} \
    && echo y | sh install.sh \
    && chmod +x /www/server/panel/install/install_soft.sh \
    && /bin/bash /www/server/panel/install/install_soft.sh 0 install php ${PHP_VERSION} nginx ${NGINX_VERSION} mysql ${MYSQL_VERSION}


COPY app.sh /

RUN chmod 777 /app.sh

CMD [ "/app.sh" ]
