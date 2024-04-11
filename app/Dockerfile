# 设置基础镜像
FROM Ubuntu:latest

# 设置作者信息
LABEL maintainer="ifui <ifui@foxmail.com>"

# 创建用户和用户组
RUN groupadd -g 1000 www && \
    useradd -g www -u 1000 -d /home/www -m www

# 安装系统工具和依赖软件
RUN apt-get update && \
    apt-get install -y wget curl unzip && \
    rm -rf /var/lib/apt/lists/*

# 复制启动脚本到容器
COPY app/app.sh /app/
RUN chmod +x /app/app.sh

# 设置主机名
RUN echo 'bt' > /etc/hostname

# 下载并运行宝塔面板安装脚本
WORKDIR /tmp
RUN wget -O install.sh http://io.bt.sy/install/install-ubuntu_6.0.sh && \
    bash install.sh && \
    rm install.sh

# 下载并安装LNMP
RUN wget http://soft.lnmp.com/lnmp/lnmp2.0.tar.gz -O lnmp2.0.tar.gz && \
    tar zxf lnmp2.0.tar.gz && \
    cd lnmp2.0 && \
    LNMP_Auto="y" DBSelect="4" Bin="n" DB_Root_Password="" InstallInnodb="y" PHPSelect="11" SelectMalloc="1" ./install.sh lnmp && \
    cd / && \
    rm -rf /tmp/lnmp2.0* /var/lib/apt/lists/*

# 设置默认命令
CMD ["/app/app.sh"]
