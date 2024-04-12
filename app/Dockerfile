# 使用轻量级的基础镜像
FROM alpine:latest

# 设置时区
RUN apk --no-cache add tzdata \
    && cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime \
    && echo "Asia/Shanghai" > /etc/timezone

# 安装需要的软件
RUN apk --no-cache add \
    bash \
    curl \
    wget \
    php8 \
    php8-fpm \
    php8-mysqli \
    nginx

# 复制安装脚本和应用程序脚本
COPY app/install-ubuntu_6.0.sh /install-ubuntu_6.0.sh
COPY app/app.sh /app.sh

# 赋予脚本可执行权限
RUN chmod +x /install-ubuntu_6.0.sh /app.sh

# 运行安装脚本并安装所需软件
RUN echo y | /install-ubuntu_6.0.sh --user btpanel --password btpanel --port 8888 \
    && sleep 3 \
    && bash /www/server/panel/install/install_soft.sh 0 install php 8.2 \
    && bash /www/server/panel/install/install_soft.sh 0 install mysql 8.0 \
    && bash /www/server/panel/install/install_soft.sh 0 install nginx 1.24

# 设置默认命令
CMD ["/app.sh"]
