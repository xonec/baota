# 使用官方的Ubuntu 20.04作为基础镜像
FROM ubuntu:20.04

# 设置时区为亚洲/上海
ENV TZ=Asia/Shanghai
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone && \
    echo 'bt' > /etc/hostname

# 复制安装脚本和应用程序脚本
COPY app/install-ubuntu_6.0.sh /install-ubuntu_6.0.sh
COPY app/app.sh /app.sh
RUN chmod +x /install-ubuntu_6.0.sh /app.sh

# 运行安装脚本并安装所需软件
RUN echo y | /install-ubuntu_6.0.sh && \
    sleep 3  && \
    bash /www/server/panel/install/install_soft.sh 0 install php 8.2 && \
    bash /www/server/panel/install/install_soft.sh 0 install mysql 8.0 && \
    bash /www/server/panel/install/install_soft.sh 0 install nginx 1.24 

# 设置默认命令
CMD ["/app.sh"]
