# 设置环境变量
ARG BAOTA_INSTALL_PATH=http://download.bt.cn/install/install_6.0.sh
ARG CENTOS_VERSION=7
ARG NGINX_VERSION=1.24
ARG PHP_VERSION=8.0
ARG MYSQL_VERSION=5.7

# 基于指定版本的CentOS官方镜像构建
FROM centos:${CENTOS_VERSION}

# 设置作者信息
LABEL maintainer="ifui <ifui@foxmail.com>"

# 创建用户组和用户
RUN groupadd -g 1000 www && useradd -g www -u 1000 -d /home/www -m www

# 安装系统工具和依赖软件
RUN yum install -y wget ca-certificates gd && \
    echo 'bt' > /etc/hostname

# 下载并安装宝塔面板
RUN wget -O install.sh ${BAOTA_INSTALL_PATH} && \
    echo y | sh install.sh && \
    chmod +x /www/server/panel/install/install_soft.sh && \
    /bin/bash /www/server/panel/install/install_soft.sh 0 install php ${PHP_VERSION} nginx ${NGINX_VERSION} mysql ${MYSQL_VERSION}

# 复制启动脚本到容器
COPY app.sh /

# 赋予启动脚本执行权限
RUN chmod +x /app.sh

# 设置默认命令 
CMD ["sh", "-c", "/app.sh && tail -f /dev/null"]
