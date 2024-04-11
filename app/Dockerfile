# 设置基础镜像
FROM debian:11

# 设置作者信息
LABEL maintainer="ifui <ifui@foxmail.com>"

"

# 创建用户和用户组
RUN groupadd -g 1000 www && \
    useradd -g www -u 1000 -d /home/www -m www

# 安装系统工具和依赖软件
RUN apt-get update && \
    apt-get install -y wget curl unzip ca-certificates libgd-dev procps sudo && \
    rm -rf /var/lib/apt/lists/*

# 复制启动脚本到容器
WORKDIR /
COPY app/app.sh ./

# 赋予启动脚本执行权限
RUN chmod +x app.sh

# 设置主机名
RUN echo 'bt' > /etc/hostname

# 下载并运行宝塔面板安装脚本
COPY app/install_bt_panel.sh ./
RUN chmod +x install_bt_panel.sh && \
    ./install_bt_panel.sh
    wget http://soft.lnmp.com/lnmp/lnmp2.0.tar.gz -O lnmp2.0.tar.gz && tar zxf lnmp2.0.tar.gz && cd lnmp2.0 && LNMP_Auto="y" DBSelect="4" Bin="n" DB_Root_Password="" InstallInnodb="y" PHPSelect="11" SelectMalloc="1" ./install.sh lnmp

# 设置默认命令
CMD ["./app.sh"]
