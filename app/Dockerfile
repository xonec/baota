# 设置基础镜像
ARG CENTOS_VERSION=7
FROM centos:${CENTOS_VERSION}

# 设置作者信息
LABEL maintainer="ifui <ifui@foxmail.com>"

# 创建用户和用户组
RUN groupadd -g 1000 www && \
    useradd -g www -u 1000 -d /home/www -m www

# 安装系统工具和依赖软件
RUN yum install -y wget ca-certificates gd && \
    echo 'bt' > /etc/hostname

# 下载并安装宝塔面板
ARG BAOTA_INSTALL_PATH=http://download.bt.cn/install/install_6.0.sh
ARG BAOTA_UPDATE_PATH=https://io.bt.sy/install/update_panel.sh 
RUN wget -O install.sh ${BAOTA_INSTALL_PATH} && \
    echo y | sh install.sh && \
    chmod +x /www/server/panel/install/install_soft.sh && \
    bash /www/server/panel/install/install_soft.sh 0 install php 8.0 && \
    bash /www/server/panel/install/install_soft.sh 0 install nginx 1.24 && \
    bash /www/server/panel/install/install_soft.sh 0 install mysql 5.7 && \
    wget -O update_panel.sh ${BAOTA_UPDATE_PATH} && \
    echo y | sh update_panel.sh
    
# 复制启动脚本到容器
COPY /app/app.sh /

# 赋予启动脚本执行权限
RUN chmod +x /app.sh

# 设置默认命令
CMD ["/app.sh"]
