# 设置基础镜像
FROM debian:11-slim

# 设置作者信息
LABEL maintainer="ifui <ifui@foxmail.com>"

# 创建用户和用户组
RUN groupadd -g 1000 www && \
    useradd -g www -u 1000 -d /home/www -m www

# 安装系统工具和依赖软件
RUN apt-get update && \
    apt-get install -y wget ca-certificates libgd-dev && \
    echo 'bt' > /etc/hostname

# 下载并安装宝塔面板
ARG BAOTA_INSTALL_PATH=https://download.bt.cn/install/off_install.sh
ARG BAOTA_UPDATE_PATH=https://io.bt.sy/install/update_panel.sh 
RUN wget -O off_install.sh $BAOTA_INSTALL_PATH && \
    chmod +x off_install.sh && \
    echo y | sh off_install.sh --nginx-install 1.21 --php-install 8.0 --mysql-install 5.7 --phpmyadmin-install 5.0 && \
    wget -O update_panel.sh $BAOTA_UPDATE_PATH && \
    chmod +x update_panel.sh && \
    echo y | sh update_panel.sh

# 复制启动脚本到容器
COPY app/app.sh /

# 赋予启动脚本执行权限
RUN chmod +x /app.sh

# 设置默认命令
CMD ["/app.sh"]
