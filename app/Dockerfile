# 使用官方的Ubuntu 20.04作为基础镜像
FROM ubuntu:20.04

# 设置时区为亚洲/上海，并修改主机名为 "bt"
ENV TZ=Asia/Shanghai \
    HOSTNAME=bt \
    DEBIAN_FRONTEND=noninteractive

# 更新软件包列表并安装所需软件
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    iproute2 net-tools iputils-ping libsasl2-dev openssh-server \
    vim libc-ares2 sudo p7zip-full curl zip unzip wget \
    libcurl4-openssl-dev expect libdatrie1 libnss3 libatk1.0-0 \
    libatk-bridge2.0-0 libgdk-pixbuf2.0-0 libgtk-3-0 libfuse2 \
    psmisc fuse libxml2-dev openssl* libssl-dev \
    fonts-wqy-microhei fonts-wqy-zenhei fonts-arphic-ukai \
    fonts-arphic-uming fontconfig xfonts-utils language-pack-zh-hans \
    autoconf g++ make && \
    ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && \
    echo $TZ > /etc/timezone && \
    echo $HOSTNAME > /etc/hostname && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# 复制安装脚本和应用程序脚本
COPY app/install-ubuntu_6.0.sh /install-ubuntu_6.0.sh
COPY app/app.sh /app.sh
RUN chmod +x /install-ubuntu_6.0.sh /app.sh

# 运行安装脚本并安装所需软件
RUN echo y | /install-ubuntu_6.0.sh --user btpanel --password btpanel --port 8888 && \
    sleep 3 && \
    bash /www/server/panel/install/install_soft.sh 0 install php 8.2 && \
    bash /www/server/panel/install/install_soft.sh 0 install mysql 8.0 && \
    bash /www/server/panel/install/install_soft.sh 0 install nginx 1.24 

# 设置默认命令
CMD ["/app.sh"]
