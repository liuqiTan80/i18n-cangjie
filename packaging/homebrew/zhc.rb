# Homebrew formula 模板（zha… zhc）——发布新版本时更新 version 与 sha256。
# 前置：GitHub 镜像 Release 已上传 zhc-<版本>-linux-x86_64.tar.gz（或托管
# 到任意可达直链）。macOS 支持需 darwin 构建产物（见 docs/全球化路线图.md P1）。
class Zhc < Formula
  desc "Write Cangjie in your mother tongue — dialect transpiler + native-language diagnostics"
  homepage "https://gitcode.com/tan80/zwCangjie"
  version "0.3.0"
  url "https://github.com/liuqiTan80/i18n-cangjie/releases/download/zhc-0.3.0/zhc-0.3.0-linux-x86_64.tar.gz"
  sha256 "f5e2822a19a7e2e202f188047fb33b26852459b0253fb16a6908d9e1492c9daa"  # TODO: 换成目标平台产物校验和

  def install
    bin.install "bin/zhc" => "zhc"
    lib.install Dir["lib/*.so"]
  end

  def caveats
    <<~EOS
      The Cangjie SDK runtime libraries are bundled; no SDK install is required.
      Language packs are included under share/lang-packs — set ZHC_LANG_PACKS
      to that directory (printed after install) to switch dialects.
    EOS
  end

  test do
    assert_match "zhc", shell_output("#{bin}/zhc help")
  end
end
