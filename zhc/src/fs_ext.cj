package zhc

@When[os == "Windows"]
import std.fs.*

@When[os != "Windows"]
import std.posix.*

/**
 * 文件删除助手（1.0 std.fs 无 delete/move 成员，实测确认）。
 *
 * Linux 等类 Unix 平台走 std.posix.unlink（尽力而为，返回值忽略）；
 * Windows 分支降级为清空内容（std.posix 的 Windows 侧无 unlink，实测确认）——
 * 至少保证敏感内容（AI 密钥/请求体）不再驻留磁盘，属 best-effort 清理。
 */

@When[os == "Windows"]
public func removeFileBestEffort(path: String): Unit {
    try {
        // Windows 侧无 unlink（std.posix 的 Windows 实现不含），降级为清空
        // 内容：敏感信息不再驻留磁盘；不存在的文件不创建
        if (exists(Path(path))) {
            File.writeTo(Path(path), Array<Byte>())
        }
    } catch (e: Exception) {
        ()   // 清理失败静默：不影响主流程
    }
}

@When[os != "Windows"]
public func removeFileBestEffort(path: String): Unit {
    let _ = unlink(path)   // 尽力而为：失败返回 -1，不抛异常、不影响主流程
}
