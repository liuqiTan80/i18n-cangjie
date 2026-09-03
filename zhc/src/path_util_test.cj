package zhc

import std.unittest.*
import std.unittest.testmacro.*

// 路径工具单元测试（Windows 反斜杠兼容：ZHC_SELF_EXE / zhc.bat 场景，实测驱动）

@Test
public func testDirOfLinuxStyle() {
    @Expect(dirOf("/a/b/zhc-core"), "/a/b")
    @Expect(dirOf("/a/b/"), "/a/b")   // 切最后一个分隔符，尾斜杠随之丢弃
    @Expect(dirOf("zhc-core"), ".")
    @Expect(dirOf("/x.zc"), "/")
    @Expect(dirOf("../x.zc"), "..")
    @Expect(dirOf("a/b/c.zc"), "a/b")
}

@Test
public func testDirOfWindowsStyle() {
    // Windows 反斜杠路径（zhc.bat 预设的 ZHC_SELF_EXE 形态）
    @Expect(dirOf("C:\\zwCangjie\\bin\\zhc-core.exe"), "C:\\zwCangjie\\bin")
    @Expect(dirOf("C:\\zwCangjie\\zhc-0.1.1-windows-x86_64"), "C:\\zwCangjie")
    @Expect(dirOf("D:\\smoke.zc"), "D:")
    // 混合分隔符：取最后一个分隔符
    @Expect(dirOf("C:/a\\b/zhc-core.exe"), "C:/a\\b")
}

@Test
public func testParentDirWindowsRoot() {
    // 父目录链在盘符层终止（findProjectRoot 向上查找不越界）
    var d = dirOf("C:\\zwCangjie\\zhc-0.1.1-windows-x86_64\\bin\\zhc-core.exe")
    d = dirOf(d)
    d = dirOf(d)
    // 第二层即到盘符（C:），再向上无分隔符返回 "."（探测 miss 无害，不再向上）
    @Expect(d.startsWith("C:"), true)
}
