# 设置基础镜像
FROM debian:11

# 设置作者信息
LABEL maintainer="ifui <ifui@foxmail.com>"

# 安装系统工具和依赖软件
RUN apt-get update && \
    apt-get install -y wget && \
    rm -rf /var/lib/apt/lists/*

# 复制启动脚本到容器
WORKDIR /
COPY app/app.sh app/off_install.sh app/update_panel.sh ./

# 赋予启动脚本执行权限
RUN chmod +x app.sh off_install.sh update_panel.sh

# 设置主机名
RUN echo 'bt' > /etc/hostname

# 运行宝塔面板安装脚本
RUN echo y | bash off_install.sh --nginx-install 1.21 --php-install 8.0 --mysql-install 5.7 --phpmyadmin-install 5.0 && \
    echo y | bash update_panel.sh

# 设置默认命令
CMD ["./app.sh"]
