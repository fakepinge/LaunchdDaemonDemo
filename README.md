# 准备工作

1、实例工程运行条件 需要更改为自己的开发者账号编译

2、工程里主进程和子进程的签名参数需要更改为自己的开发者账号签名后的参数

# 一、前言背景

1、前言

在MacOS App开发中，有一些操作需要管理员权限，需要弹出认证对话框让用户输入账号和密码，这个过程就是MacOS App提权的过程。

2、方案

目前主要有下面三种方式：

- AuthorizationExecuteWithPrivileges()
- 使用ServiceManagement.framework注册LaunchdDaemon
- 使用AppleScript

3、结论

经过调研后，采取第二种方案LaunchdDaemon，并在LaunchdDaemon提权失败后兼容使用AppleScript继续授权。

4、示例

示例工程地址 [LaunchdDaemonDemo](https://github.com/fakepinge/LaunchdDaemonDemo.git)

# 二、LaunchdDaemon提权介绍

1、注册`LaunchdDaemon`的常用方法是通过`launchd`工具加载一个与`Daemon`程序相关的标准的`plist`文件，由于`launchd`需要高权限运行，所以启动的子程序自然也是高权限运行；

2、传统过程一般放在 **PKG** 的安装脚本中完成，但当前越来越多的软件摒弃了 **PKG** 的打包方式，而是直接选择了打包成 App 来提升用户体验，此时安装辅助帮助工具的工作也就要放到 App 运行过程中，使用`ServiceManagement`的 API 来完成该操作过程；

3、通过`ServiceManagement`注册`LaunchdDaemon`是苹果推荐的一种提权方式，官方也提供了一个 SMJobBless 的 [Demo](https://developer.apple.com/library/archive/samplecode/SMJobBless/Introduction/Intro.html)，需要用苹果开发者账号编译。具体思路是使用`Security.framework`和`ServiceManagement.framework`两个库，把需要`root`权限的操作封装成一个 `Command Line Tool` Target，作为项目的子程序，把该子程序注册`LaunchdDaemon；`

4、注册成为`LaunchdDaemon`后：

子进程的可执行文件会被放在系统目录 `/Library/PrivilegedHelperTools`

相应的`plist`配置文件会被放在 `/Library/LaunchDaemons`，`Launchd`加载子进程会需要读取该配置文件，过程较为复杂，可以学习一下 SMJobBless 的 [Demo](https://developer.apple.com/library/archive/samplecode/SMJobBless/Introduction/Intro.html) 。

# 三、注册 LaunchdDaemon步骤

以全新的工程做示例，工程名为：`LaunchdDaemonDemo`

1、创建一个MacOS App的工程项目`LaunchdDaemonDemo`，bundleId为：com.fakepinge.LaunchdDaemon.LaunchdDaemonDemo

2、在`LaunchdDaemonDemo.entitlements` 配置文件中关闭沙盒，`App Sandbox`设置为 NO

3、创建一个新的 MacOS Target，选择 Command Line Tool 类型，命名为：`ProxyConfigHelper`，bundleId为：com.fakepinge.LaunchdDaemon.helper，将该Target 名修改为与bundleId一致，com.fakepinge.LaunchdDaemon.helper

4、`LaunchdDaemonDemo` 主工程 Info.plist 文件配置相关参数

```plain
<!-- 主工程的签名参数 -->
<key>SMAuthorizedClients</key>
<array>
    <string>identifier "com.fakepinge.LaunchdDaemon" and anchor apple generic and certificate leaf[subject.CN] = 0x4170706c6520446576656c6f706d656e743a20e79fa5e5b9b320e883a120283543434d355a5652343729 and certificate 1[field.1.2.840.113635.100.6.2.1] /* exists */</string>
</array>
<!-- 子进程的签名参数 -->
<key>SMPrivilegedExecutables</key>
<dict>
    <key>com.fakepinge.LaunchdDaemon.helper</key>
    <string>identifier "com.fakepinge.LaunchdDaemon.helper" and anchor apple generic and certificate leaf[subject.CN] = 0x4170706c6520446576656c6f706d656e743a20e79fa5e5b9b320e883a120283543434d355a5652343729 and certificate 1[field.1.2.840.113635.100.6.2.1] /* exists */</string>
</dict>
```

5、`ProxyConfigHelper` 目录下创建 Info.plist 文件，配置相关参数，关联 Info.plist 文件在配置中

```plain
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
    <dict>
        <key>CFBundleIdentifier</key>
        <!-- 子进程bundleId -->
        <string>com.fakepinge.LaunchdDaemon.helper</string>
        <key>CFBundleInfoDictionaryVersion</key>
        <string>1.0</string>
        <key>CFBundleName</key>
        <!-- 同bundleId -->
        <string>com.fakepinge.LaunchdDaemon.helper</string>
        <key>CFBundleShortVersionString</key>
        <!-- 子进程版本号 -->
        <string>1.0.0</string>
        <key>CFBundleVersion</key>
        <string>1</string>
        <key>SMAuthorizedClients</key>
        <!-- 配置主进程的签名参数 -->
        <array>
            <string>identifier "com.fakepinge.LaunchdDaemon" and anchor apple generic and certificate leaf[subject.CN] = 0x4170706c6520446576656c6f706d656e743a20e79fa5e5b9b320e883a120283543434d355a5652343729 and certificate 1[field.1.2.840.113635.100.6.2.1] /* exists */</string>
        </array>
    </dict>
</plist>
```

6、`ProxyConfigHelper` 目录下创建 Launchd.plist 文件，配置相关参数

```plain
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
    <dict>
        <key>AssociatedBundleIdentifiers</key>
        <!-- 主进程bundleId -->
        <string>com.fakepinge.LaunchdDaemon</string>
        <key>Label</key>
        <!-- 子进程bundleId -->
        <string>com.fakepinge.LaunchdDaemon.helper</string>
        <key>MachServices</key>
        <dict>
            <!-- 子进程bundleId -->
            <key>com.fakepinge.LaunchdDaemon.helper</key>
            <true/>
        </dict>
    </dict>
</plist>
```

7、`ProxyConfigHelper` Target 中配置 Other Linker Flags

```plain
// Info.plist 的路径
-sectcreate __TEXT __info_plist "$(SRCROOT)/ProxyConfigHelper/Info.plist"
// Launchd.plist 的路径
-sectcreate __TEXT __launchd_plist "$(SRCROOT)/ProxyConfigHelper/Launchd.plist"
```

8、`LaunchdDaemonDemo` Target 配置依赖 `ProxyConfigHelper` Target

![20230630160242.jpg](https://p3-juejin.byteimg.com/tos-cn-i-k3u1fbpfcp/eb016d4e809b4525b0087649f82c6756~tplv-k3u1fbpfcp-zoom-1.image)

工程中两个 Target 配置好当前的开发者证书，编译Build 生成 Product

9、`LaunchdDaemonDemo` Target Build Phases 配置 Copy Files

Destination 选择 Wrapper，Subpath 配置 `Contents/Library/LaunchServices`

添加可执行文件 com.fakepinge.LaunchdDaemon.helper

![20230630144929.jpg](https://p3-juejin.byteimg.com/tos-cn-i-k3u1fbpfcp/65acdb235d5d4c25b4dab5389ed5d9bb~tplv-k3u1fbpfcp-zoom-1.image)

10、`Launchd`安装守护进程是个需要很高安全性的动作，所以应用签名是必不可少的，生成对应签名参数写入第四步和第五步的配置文件中；

```plain
// 终端命令
codesign -d -r - 编译出的Product包地址(主进程)
```

获取主工程`LaunchdDaemonDemo` 编译出的Product .app包(LaunchdDaemonDemo)的签名；

```plain
codesign -d -r - xxx/LaunchdDaemonDemo.app
Executable=xxx/LaunchdDaemonDemo.app/Contents/MacOS/LaunchdDaemonDemo
designated => identifier "com.fakepinge.LaunchdDaemon" and anchor apple generic and certificate leaf[subject.CN] = 0x4170706c6520446576656c6f706d656e743a20e79fa5e5b9b320e883a120283543434d355a5652343729 and certificate 1[field.1.2.840.113635.100.6.2.1] /* exists */
```

获取子进程`ProxyConfigHelper` 编译出的可执行文件(com.fakepinge.LaunchdDaemon.helper)的签名

```plain
codesign -d -r - xxx/com.fakepinge.LaunchdDaemon.helper
Executable=xxx/com.fakepinge.LaunchdDaemon.helper
designated => identifier "com.fakepinge.LaunchdDaemon.helper" and anchor apple generic and certificate leaf[subject.CN] = 0x4170706c6520446576656c6f706d656e743a20e79fa5e5b9b320e883a120283543434d355a5652343729 and certificate 1[field.1.2.840.113635.100.6.2.1] /* exists */
```

designated => 后面的部分就是我们需要的“签名参数信息”
11、在需要使用的高权限的地方写入授权代码

     可以参考 SMJobBless 的 [Demo](https://developer.apple.com/library/archive/samplecode/SMJobBless/Introduction/Intro.html) (SMJobBlessAppController.m)的授权代码

当前示例工程 [LaunchdDaemonDemo](https://github.com/fakepinge/LaunchdDaemonDemo.git) 也包含授权代码 (PrivilegedHelperManager.swift)

12、运行测试，调用授权代码，弹出安装辅助帮助，输入管理员密码授权，授权成功后就可以在

`ProxyConfigHelper` 子进程项目中写需要高权限的操作。

13、是否授权成功的查看方式

```plain
系统目录/Library/LaunchDaemons 写入了plist文件
com.fakepinge.LaunchdDaemon.helpe.plist
系统目录/Library/PrivilegedHelperTools 写入了可执行文件
com.fakepinge.LaunchdDaemon.helper
以上都写入成功了，说明辅助帮助工具安装成功
```

![20230630161445.jpg](https://p3-juejin.byteimg.com/tos-cn-i-k3u1fbpfcp/c8dd297b8d0747e08ab875790740a562~tplv-k3u1fbpfcp-zoom-1.image)

# 四、AppleScript方案

1、方案介绍

当注册LaunchdDaemon失败后，可以启动AppleScript授权，原理是使用shell脚本写入plist文件和可执行文件，使用时认证窗口的提示信息是“xxx wants to make changes”

![20230630161521.jpg](https://p3-juejin.byteimg.com/tos-cn-i-k3u1fbpfcp/3d807d263e0e4310b8967e4fd49c294c~tplv-k3u1fbpfcp-zoom-1.image)

2、实现方案

当前示例工程 [LaunchdDaemonDemo](https://github.com/fakepinge/LaunchdDaemonDemo.git)  (PrivilegedHelperManager+Legacy.swift)

```plain
// 安装脚本
func getInstallScript() -> String {
    let appPath = Bundle.main.bundlePath
    let bash = """
    #!/bin/bash
    set -e

    plistPath=/Library/LaunchDaemons/\(PrivilegedHelperManager.machServiceName).plist
    rm -rf /Library/PrivilegedHelperTools/\(PrivilegedHelperManager.machServiceName)
    if [ -e ${plistPath} ]; then
    launchctl unload -w ${plistPath}
    rm ${plistPath}
    fi
    launchctl remove \(PrivilegedHelperManager.machServiceName) || true

    mkdir -p /Library/PrivilegedHelperTools/
    rm -f /Library/PrivilegedHelperTools/\(PrivilegedHelperManager.machServiceName)

    cp "\(appPath)/Contents/Library/LaunchServices/\(PrivilegedHelperManager.machServiceName)" "/Library/PrivilegedHelperTools/\(PrivilegedHelperManager.machServiceName)"

    echo '
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
    <key>Label</key>
    <string>\(PrivilegedHelperManager.machServiceName)</string>
    <key>MachServices</key>
    <dict>
    <key>\(PrivilegedHelperManager.machServiceName)</key>
    <true/>
    </dict>
    <key>Program</key>
    <string>/Library/PrivilegedHelperTools/\(PrivilegedHelperManager.machServiceName)</string>
    <key>ProgramArguments</key>
    <array>
    <string>/Library/PrivilegedHelperTools/\(PrivilegedHelperManager.machServiceName)</string>
    </array>
    </dict>
    </plist>
    ' > ${plistPath}

    launchctl load -w ${plistPath}
    """
    return bash
}
```

# 五、主进程与子进程通信（XPC）

1、XPC 子进程的连接监听逻辑

```plain
// 子进程监听
self.listener = [[NSXPCListener alloc] initWithMachServiceName:@"com.fakepinge.LaunchdDaemon.helper"];
...
- (BOOL)listener:(NSXPCListener *)listener shouldAcceptNewConnection:(NSXPCConnection *)newConnection {   
    // Configure the connection.
    // First, set the interface that the exported object implements.
    newConnection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(ProxyConfigRemoteProcessProtocol)];
    // Next, set the object that the connection exports. All messages sent on the connection to this service will be sent to the exported object to handle. The connection retains the exported object.
    newConnection.exportedObject = self;
    // Resuming the connection allows the system to deliver more incoming messages.
    [newConnection resume];
    // Returning YES from this method tells the system that you have accepted this connection. If you want to reject the connection for some reason, call -invalidate on the connection and return NO.
    return YES;
}
// ProxyConfigRemoteProcessProtocol 定义的通信协议
// 主进程和子进程声明在协议中的Api进行交互通信
// 需要特别说明的一点是，XPC 连接建立起来之后，主进程方就能获取到上面的逻辑里的 exportedObject，而再上一行的 exportedInterface 是声明这个对象在这次 XPC 通讯中会遵循的协议。
// 换句话说，主进程方方会把连接上的 XPC 直接当作一个对象来操作，这个对象的消息传递是异步的，所以在调用的时候要小心避免卡主线程。
```

2、XPC 主进程启动子进程建立连接

```plain
/// 建立连接
func createConnectionHelper(failture: (() -> Void)? = nil) -> ProxyConfigRemoteProcessProtocol? {
    connection = NSXPCConnection(machServiceName: PrivilegedHelperManager.machServiceName, options: NSXPCConnection.Options.privileged)
    connection?.remoteObjectInterface = NSXPCInterface(with: ProxyConfigRemoteProcessProtocol.self)
    connection?.invalidationHandler = {
    }
    connection?.resume()
    guard let helper = connection?.remoteObjectProxyWithErrorHandler({ error in
        failture?()
    }) as? ProxyConfigRemoteProcessProtocol else { return nil }
    processHelper = helper
    return processHelper
}
/// 通过 machServiceName 找到特定 XPC 并建立连接，建议把这个连接connection实例保存起来，避免重复创建带来别的问题
/// 这一步参数里的协议就是我们在 XPC 中声明的协议，两边的协议要对得上才能拿到 XPC 中 exportedObject 暴露出来的正确对象
/// 手动调用 resume 来建立连接，调用后 XPC 子进程那边才会收到 -[listener:shouldAcceptNewConnection:] 回调
/// 使用 processHelper 调用协议方法来进行通信
```

3、子进程启动监听

```plain
int main(int argc, const char * argv[]) {
    @autoreleasepool {
        [[NSProcessInfo processInfo] disableSuddenTermination];
        [[ProxyConfigHelper new] run];
        NSLog(@"ProxyConfigHelper exit");
    }
    return 0;
}
- (void)run {
    [self.listener resume];
    self.checkTimer =
    [NSTimer timerWithTimeInterval:5.f target:self selector:@selector(connectionCheckOnLaunch) userInfo:nil repeats:NO];
    [[NSRunLoop currentRunLoop] addTimer:self.checkTimer forMode:NSDefaultRunLoopMode];
    while (!self.shouldQuit) {
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:2.0]];
    }
}
```

# 六、注意事项

1、子进程只做高权限的操作，其余无需权限的操作尽量放在主进程

2、子进程里使用源码开发代码，如需要引入库文件，请使用静态库，子进程编译会将库文件编 译进可执行文件中，会增加可执行文件包的大小
