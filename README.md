# clipboard-go
## clipboard-go是什么

一组应用程序，用于在手机和电脑之间安全快速的传递剪切板信息，也支持小文件或图片。



## 为什么选择clipboard-go

- 安全 - 所有数据使用AES算法加密传递(即使是局域网，也有人希望更安全，比如我)
- 快速 - 使用Golang和Flutter编写，界面简洁，专注于信息传递
- 全面 - 局域网内自动选择ip，当设备之间不在同一网段时，依然可以使用web端同步
- 开源 - 免费无广告，API全部开放，可选择自己定制app



## 如何使用

> **注意**：配置阶段需要确保电脑和手机处于同一网络中。



### 下载

github：[Releases · Doraemonkeys/clipboard-go](https://github.com/Doraemonkeys/clipboard-go/releases)

蓝奏云：[clipboard-go 蓝奏云](https://wwxz.lanzouw.com/b03efpa1e) 密码:c1at



手机端如果不知道选择哪个安装就选 app-armeabi-v7a-release.apk 。



### PC端

1. 解压 clipboard-go-amd64-windows.rar 到任意目录

2. 双击exe文件运行：

      请点击允许windows网络防火墙，**注意**勾选公用网络(大胆的勾选，所有内容均已加密)。

   ![image-20230621225600846](https://raw.githubusercontent.com/Doraemonkeys/picture/master/1/202306212303629.png)

   可以观察到任务栏下出现app的图标，同时生成了默认配置文件到当前目录。
   
   ![image-20230621192706843](https://raw.githubusercontent.com/Doraemonkeys/picture/master/1/202306212049312.png)

   如果你忘记勾选公用网络，请到Windows防火墙手动设置，或者确保你正在使用专用网络。

   ![image-20230623220546743](E:/Doraemon/Pictures/Typora/2023003/image-20230623220546743.png)





3. 打开默认配置文件`config.yaml`，复制secretKeyHex(注意不要复制到空格)，手机端需要用到。

<img src="https://raw.githubusercontent.com/Doraemonkeys/picture/master/1/202306212049362.png" alt="image-20230621192929505" style="zoom: 67%;" />



### 移动端

1. 安装APP(如果不知道选择哪个安装就选 app-armeabi-v7a-release.apk)。
2. 打开APP，点击右下角的加号配置。



3. IP不用填！，Secret Key 填刚才复制的，Auto Select 填true(这表示app将根据密钥自动选择ip)。

<img src="E:/Doraemon/Pictures/Typora/2023003/Screenshot_2023-06-23-21-57-15-126-edit_com.example.clipboard.jpg" style="zoom:33%;" />

4. 最后，激动人心的时刻到了，手机随便复制一段文字，打开app点击Paste text，电脑瞬间弹出通知，恭喜你已经成功完成了配置，可以愉快的使用了。



### 注意事项

1. 一直转圈圈说明你电脑端配置有问题，比如wifi设置了公用网络。
2. 圈圈不动了说明app正在加密上传，不是卡住了，这是由于我不熟悉app开发，暂时搞不定(手动狗头)。
3. 出现情况2说明文件比较大，请不要传输大文件，这不是软件设计的初衷。



### 不在同一网络的解决方案

#### 1. 使用内网穿透软件

如果是Tailscale，只需要把电脑ip换成Tailscale分配的IP，Auto Select填false就行了，其他工具自行测试。



#### 2. 使用别人搭好的服务器

本工具内置了一个，只需要新建配置，ip填web，对你没有看错，就是这三个字母web。Secret Key 填刚才电脑上复制的。使用此功能需要在电脑上手动点击软件，复制到剪切板。

<img src="E:/Doraemon/Pictures/Typora/2023003/Screenshot_2023-06-23-22-00-49-124_com.example.clipboard.png" style="zoom:33%;" />



web传递信息的原理是使用了 https://ko0.com/ 网站。虽然方便，但希望各位尽量只在紧急情况下使用这个功能，把别人网站搞垮了大家就都没得用了。



## 跨平台情况

目前仅支持Android与Windows。



### 移动端

移动端代码使用flutter编写，理论上支持安卓和IOS，但由于作者对IOS不熟悉，也没有相关设备测试，所以暂不支持，动手能力强的可以自己尝试编译。



### PC

Pc端代码使用Golang编写，代码中主要的库都是跨平台的，但是作者在实现选择文件时使用了Windows的API，所以想要提供其他平台的支持，就需要高手稍微修改一下源代码，作者能力尚浅，欢迎高手来PR。



## API

### http POST /copy

TODO

### http POST /paste

TODO

### http POST /ping

TODO

## 展望

本人不太熟悉Flutter，希望能有大佬能重构一下dart代码，优化一下界面 :)doge



设计协议的代码我可以很快整出来，app端的交互我是真不太好设计，主要是我flutter真不太会。



所以如果遇到bug，能忍就忍一忍，不能忍了再踢我一脚，就这样，over!
