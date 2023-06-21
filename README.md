# clipboard-go
## clipboard-go是什么

一组应用程序，用于在手机和电脑之间安全快速的传递剪切板信息，也支持小文件或图片。



## 为什么选择clipboard-go

- 安全 - 所有数据使用AES算法加密传递(即使是局域网，有人也希望更安全，比如我)
- 快速 - 使用Golang和Flutter编写，界面简洁，专注于信息传递
- 全面 - 当设备之间不在同一局域网时，依然可以使用web端同步
- 开源 - 免费无广告，API全部开放，可选择自己定制app



## 如何使用

> **注意**：配置阶段需要确保电脑和手机处于同一网络中。



### 下载

github：[Releases · Doraemonkeys/clipboard-go](https://github.com/Doraemonkeys/clipboard-go/releases)

蓝奏云：[clipboard-go 蓝奏云](https://wwxz.lanzouw.com/b03efpa1e) 密码:c1at



### PC端

1. 解压 clipboard-go-amd64-windows.rar 到任意目录
2. 双击exe文件运行，可以观察到任务栏下出现app的图标，同时生成了默认配置文件到当前目录。

![image-20230621192706843](https://raw.githubusercontent.com/Doraemonkeys/picture/master/1/202306212049312.png)

3. 打开默认配置文件`config.yaml`，复制secretKeyHex(注意不要复制到空格)，手机端需要用到。

<img src="https://raw.githubusercontent.com/Doraemonkeys/picture/master/1/202306212049362.png" alt="image-20230621192929505" style="zoom: 67%;" />

4. 查看电脑ipv4，cmd或PowerShell中执行命令：`ipconfig`，找到无线局域网适配器 WLAN的ipv4地址，记录下来。

> 为避免局域网内ip变化，建议为电脑设置静态ip。
>



### 移动端

1. 安装APP(如果不知道选择哪个安装就选 app-armeabi-v7a-release.apk)。
2. 打开APP，点击右下角的加号配置(下面会新建两次)。



3. 第一次新建：IP填web，secretKeyHex填刚才复制的，添加web配置用于手机电脑不在同一局域网传递信息。

<img src="https://raw.githubusercontent.com/Doraemonkeys/picture/master/1/202306212049453.png" alt="Screenshot_2023-06-21-19-38-02-706_com.example.clipboard" style="zoom:33%;" />

4. 第二次新建：IP填电脑的IP，secretKeyHex填刚才复制的。用于局域网内传递信息。

<img src="https://raw.githubusercontent.com/Doraemonkeys/picture/master/1/202306212049519.png" style="zoom: 33%;" />

### 注意事项

web传递信息的原理是https://ko0.com/网站。

## 跨平台情况

目前仅支持Android与Windows。



### 移动端

移动端代码使用flutter编写，理论上支持安卓和IOS，但由于作者对IOS不熟悉，也没有相关设备测试，所以暂不支持，动手能力强的可以自己尝试编译。



### PC

Pc端代码使用Golang编写，代码中主要的库都是跨平台的，但是作者在实现选择文件时使用了Windows的API，所以想要提供其他平台的支持，就需要高手稍微修改一下源代码，作者能力尚浅，欢迎高手来PR。



## API

TODO



## 展望

计划添加局域网内自动选择ip的功能。



本人不太熟悉Flutter，希望能有大佬能重构一下dart代码，优化一下界面 :)doge
